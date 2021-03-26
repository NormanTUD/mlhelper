#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;


my $maindir = "/sw/installed/";

sub msg ($;$) {
        my $msg = shift or die "Empty message";
        my $title = shift // "Message";

        system(qq#whiptail --title "$title" --msgbox "$msg" 8 78#);
}

sub yesno ($;$) {
        my $msg = shift or die "Empty message";
        my $title = shift // "Question";

        system(qq#whiptail --title "$title" --yesno "$msg" 8 78#);
        return 1 if $? == 0;
        return 0;
}

sub input ($;$) {
        my $title = shift // "Input";
        my $msg = shift or die "Empty message";

        my $command = qq#whiptail --inputbox "$title" 15 80 "" --title "$msg" 3>&1 1>&2 2>&3#;


        my $input = '';

        open CMD,'-|', $command or die $@;
        my $line;
        while (defined($line = <CMD>)) {
            $input .= $line
        }
        close CMD;
        my $retval = $?;

        return $input if $retval == 0;
        exit;
}

sub menu ($$@) {
        my $message = shift;
        my $title = shift;
        my $name = shift;
        my $version = shift;
        my @items = @_;

        my $menustr = "";
        foreach my $item (@items) {
                $menustr .= "'".$item->{version}->{name}.'/'.$item->{version}->{version}."-".$item->{version}{stack}."' '".$item->{version}->{version}."' ";
        }


        my $command = qq#whiptail --title "$title" --menu "$message" 30 100 16 $menustr "pip3" "install locally via pip3" "virtualenv" "install locally in a virtual env" "conda" "install locally in conda env" "exit" "exit" 2> .reply_answer#;

        system $command;
        my $slurped = read_file(".reply_answer");
        unlink ".reply_answer" or warn $!;

        exit if $slurped eq "exit";
        return "ml $slurped" unless $slurped =~ m#^virtualenv|conda|pip3?#;
        return "$slurped-->$name==$version";
}

sub read_file {
        my $filename = shift;

        open my $fh, '<', $filename or die "Can't open file $!";
        my $file_content = do { local $/; <$fh> };
        close $fh;
        return $file_content;
}

sub get_possible_matches {
        my ($name, $version) = @_;

        die "name undefined" unless defined $name;

        opendir my $dir, $maindir or die "Cannot open directory: $!";
        my @files = readdir $dir;
        closedir $dir;

        my @possible_versions = ();
        foreach my $file_or_dir (@files) {
                if(-d "$maindir/$file_or_dir") {
                        if (uc $file_or_dir eq uc $name) {
                                opendir my $dir, "$maindir/$file_or_dir" or die "Cannot open directory: $!";
                                my @files_in_module_dir = readdir $dir;
                                closedir $dir;

                                foreach my $versiondir (@files_in_module_dir) {
                                        my $thisdir = "$maindir/$file_or_dir/$versiondir";
                                        if(-d $thisdir) {
                                                # 1.13.1-fosscuda-2019a-Python-3.7.2
                                                if($versiondir =~ m#^(\d+(?:\.\d+)+)-(.*)$#) {
                                                        my ($version, $stack) = ($1, $2);
                                                        push @possible_versions, {"stack" => $stack, "version" => $version, "name" => $file_or_dir };
                                                }
                                        }

                                }

                        }
                }
        }
        return @possible_versions;
}

sub find_version {
        my ($name, $version) = @_;

        my @possible_versions = get_possible_matches($name, $version);

        # exakte matche finden

        foreach my $possible_version (sort { version->parse( $a->{version} ) <=> version->parse( $b->{version} ) } @possible_versions) {
                my ($tversion, $stack, $tname) = ($possible_version->{version}, $possible_version->{stack}, $possible_version->{name});
                if(lc $name eq lc $tname) {
                        if ($version eq $tversion) {
                                return "ml $name/$tversion-$stack";
                        }
                }
        }

        # ungefaehre matche finden

        my @possible_versions_narrower = ();

        foreach my $possible_version (sort { version->parse( $a->{version} ) <=> version->parse( $b->{version} ) } @possible_versions) {
                my ($tversion, $stack, $tname) = ($possible_version->{version}, $possible_version->{stack}, $possible_version->{name});
                if(lc $name eq lc $tname) {
                        if ($tversion =~ m#^$version#) {
                                push @possible_versions_narrower, $possible_version; 
                        }
                }
        }

        if (@possible_versions_narrower) {
                return +("=========================> One of these:", (map { "ml $_->{name}/$_->{version}-$_->{stack}" } @possible_versions_narrower), "<==================================");
        }

        if($version) {
                if(yesno "No matching versions found for $name $version. Do you want to expand your search to *nearest* versions?", "Sorry") {
                        my @closest_versions = ();
                        my $myversion = get_comparable_version_number($version);
                        my @version_split = split(/\./, $version);

                        foreach my $this_version (@possible_versions) {
                                my @this_version_split = split(/\./, $this_version->{version});
                                if ($version_split[0] == $this_version_split[0]) {
                                        push @closest_versions, { "version" => $this_version, "compareablenumber" => get_comparable_version_number($this_version->{version}) };
                                }
                        }
                        my @sorted = sort { int($a->{compareablenumber} <=> $b->{compareablenumber}) } @closest_versions;

                        my $chosen = menu "The following versions have been found, ranked in probably that they will work as you expect (first = most likely). The version you wanted was: $version.", "MENU", $name, $version, @sorted;

                        return ($chosen);
                }
        } else {
                print "Could not find any modules for the search $name\n";
                print "For more detailled search for modules like $name, you have to enter a version number (like $name==1.25.6)\n";
        }

        return ();
}

sub get_comparable_version_number {
        my $version = shift;
        my @version_split = split(/\./, $version);

        my $number_of_version_positions = scalar @version_split;

        my $str = '';

        foreach my $i (@version_split) {
                if($i =~ m#^\d*$#) {
                        $str .= sprintf("%06d", $i);
                }

        }
        my $int = int $str;

        return $int;
}

sub main () {
        my @needed_modules = ();
        while (my $needed = input("Please name the module you need in Python-Syntax, possibly with version-number, like:\ntensorflow==1.15\nEnter nothing to end this list.", "title")) {
                last unless $needed;
                push @needed_modules, $needed;
        }

        my %modulenames_and_versions = ();

        foreach my $module (@needed_modules) {
                if ($module =~ m#^(.*?)(?:={1,}(.*))?$#) {
                        my $name = $1;
                        my $version = $2 // "any";

                        $version =~ s#[^0-9\.]##g;

                        suggestion_string($name, $version);
                } else {
                        warn Dumper "Unparsable module name: $module";
                }
        }

}

sub suggestion_string {
        my ($name, $version) = @_;
        my @possible_versions = find_version($name, $version);

        my $contains_virtualenv = 0;
        my $contains_pip = 0;
        my $contains_conda = 0;

        foreach my $possible_version_i (0 .. $#possible_versions) {
                my $possible_version = $possible_versions[$possible_version_i];
                if($possible_version =~ m#virtualenv-->(.*)#) {
                        $contains_virtualenv = 1;
                } elsif($possible_version =~ m#pip(3?)-->(.*)#) {
                        $contains_pip = 1;
                } elsif($possible_version =~ m#conda-->(.*)\n#) {
                        $contains_conda = 1;
                }
                $possible_version_i++;
        }

        if ($contains_pip) {
                print "======= Explanation pip =========\n";
                print "pip is pythons module system.\n";
                print "this will install this to your\n";
                print "home directory! Other users\n";
                print "will have to do this, too!\n";
                print "Will not work on Power-PC-Machines\n";
                print "like Machine-Learning-Partition!\n";
        }

        if($contains_conda) {
                print "======= Explanation conda ========\n";
                print "Like virtualenv, but more general.\n";
                print "a way to create a specific environment\n";
                print "in which you can install environments\n";
                print "more or less as you wish\n";
                print "On x86_64 machines, you have to load\n";
                print "ml Miniconda2\n"
        }

        if($contains_virtualenv) {
                print "======= Explanation virtualenv =======\n";
                print "Like conda , but only for python.\n";
                print "a way to create a specific environment\n";
                print "in which you can install environments\n";
                print "more or less as you wish. Use pip there.\n";
                print "How to set up:\n";
                print "python3 -m venv \$ENVNAME\n";
                print "source \$ENVNAME/bin/activate\n";
                print "pip3 install programm==version\n";
                print "... do your stuff...\n";
                print "deactivate\n";
        }

        print "==============================================================\n";
        print "Try running ml purge if this does not work\n";
        print "==============================================================\n";

        if($contains_conda || $contains_virtualenv || $contains_pip) {
                print "=====================> CODE: ============================>\n";
        }


        if($contains_conda + $contains_virtualenv + $contains_pip >= 2) {
                print "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! WARNING !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n";
                print "Its not recommended to use more than one of pip, virtualenv and conda\n";
        }

        if($contains_virtualenv) {
                print "source \$ENVNAME/bin/activate\n";
        }
        foreach my $possible_version_i (0 .. $#possible_versions) {
                my $possible_version = $possible_versions[$possible_version_i];
                if($possible_version =~ m#virtualenv-->(.*)#) {
                        print "pip3 install --user $1\n";
                } elsif($possible_version =~ m#pip(3?)-->(.*)#) {
                        print "pip$1 install --user $2\n";
                } elsif($possible_version =~ m#conda-->(.*)#) {
                        print "conda install $1\n";
                } elsif($possible_version =~ m#virtualenv-->(.*)#) {
                        print "pip$1 install --user $2\n";
                } else {
                        print "$possible_version\n";
                }
                $possible_version_i++;
        }
}

#die "1.10.0: ".get_comparable_version_number("1.10.0")."\n"."1.11.0: ".get_comparable_version_number("1.11.0");

main
