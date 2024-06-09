#!/usr/bin/env perl

use warnings;
use strict;

use YAML qw( LoadFile );
use Cwd;
use Sys::Hostname;
use Getopt::Long qw( :config posix_default bundling no_ignore_case );
use File::Path qw( make_path );
use File::Find;
use JSON;

my $path;          # designating a generic path to search
my $disable;       # used once, will toggle on chmod, used twice, will toggle on suspension
my $force;         # boolean to bypass y/n input verification for any disable actions
my $limit;         # the max filesize for directories find will descend into
my $ctime;         # the max difference in ctime when looking for similarly modified files
my $file_types;    # the type of files being searched
my $admin_log_on;  # if set, path admin logs (full file paths) are saved at
my $cust_log_on;   # boolean that for if customer logs are enabled or not
my $quiet;         # can be used (-q, -qq, or -qqq) to supress some/all output during runtime
my $tracking;      # when passed, tracks scans in a json document
my $debug;         # have the find subroutine output what it's doing as it runs
my $help;          # toggle the help menu
my $line_length = 300000;     #the max line length in bytes before a file is skipped
my $filesize    = 100000000;  #the max file size in bytes before it is skipped
my $date        = localtime();

# command line arguments
GetOptions(
    'path|p=s'         => \$path,
    'disable|d+'       => \$disable,
    'force'            => \$force,
    'limit|l=i'        => \$limit,
    'length|n=i'       => \$line_length,
    'size|z=i'         => \$filesize,
    'ctime|t=i'        => \$ctime,
    'files|f=s'        => \$file_types,
    'admin-logs|a:s'   => \$admin_log_on,
    'customer-logs|c'  => \$cust_log_on,
    'no-vzroot|x'      => \$x_vzroot,
    'quiet|q+'         => \$quiet,
    'track|T'          => \$tracking,
    'debug'            => \$debug,
    'help|h'           => \$help,
) or die( "Incorrect usage of options. See --help for more information.\n" );

if ( $help ) { help_menu(); }

# data structure for programatic use
# instead of just line by line user output
# user output can be created with this ...
my %data;

## scan history
##
$data{'scans'} = {};
$data{'scans'}{'count'} = 0;
$data{'scans'}{'dates'} = [];
$data{'scans'}{'tickets'} = [];
$data{'scans'}{'last_run'} = $date;

## data matches - found files
##
$data{'matches'} = {};
$data{'matches'}{'count'} = 0;
$data{'matches'}{'files'} = [];

## close matches
##
$data{'ctimes'} = {};
$data{'ctimes'}{'count'} = 0;
$data{'ctimes'}{'files'} = [];

## skipped directories
##
$data{'skipped'} = {};
$data{'skipped'}{'count'} = 0;
$data{'skipped'}{'dirs'} = [];


###################################################################################################
### validations on input
###################################################################################################

#ensure this is running via sudo and not directly as root
validate_sudo() or
    die "This may only run via sudo.  See --help for more information.\n";

###################################################################################################
### variable declarations and run-time tests
###################################################################################################

#set a timestamp that can be used for logs, uses localtime not gmtime simply for user readability
my $logtime            = declare_logtime();

#determine/test search and log variables
my $search_path       = ( $path ? $path : "./" );
my $cust_log          = "";
my $dir_limit         = declare_dir_limit( 67108864 );

#determine/test admin log
my $admin_log          = create_admin_log();

#default search_ctime to 3 if nothing was input, smooth out negative numbers to zero
my $search_ctime       = ( !( defined $ctime ) ? 3 : ( $ctime < 1 ) ? 0 : $ctime );

#build the file type list that will be searched or default to php|html|pl|js
my $search_file_types  = declare_file_types();

#default incremental options to 0
$quiet = 0 if ( !$quiet );
$disable = 0 if ( !$disable );

###################################################################################################
### execute searches
###################################################################################################

my $signatures;
my %signatures;      #hash of malicious signatures, key=incremented index : value=regex
my %found_files;     #hash of matches, key=filepath : value=regex matched
my %found_ctimes;    #list of ctimes found, key=ctime : value=1 (same matches can simply rehash to 1)
my @skipped_dirs;    #list of directories that were skipped over due to $search_limit
my $skip_files;      #list of files that should be skipped as indicated in dirty_find_configs.yaml
my @skipped_files;   #list of files that were skipped due to inclusion in dirty_find_configs.yaml
my @long_lines;      #list of files that were skipped due to having lines over a given length
my @large_files;     #list of files that were skipped due to being larger than a given size
my @false_positives; #list of files we consider to be (almost always) false positives and therefore skipped

( $signatures, $skip_files ) = generate_configs();
%signatures                  = %$signatures;

print "Searching for matching signatures...\n" if ( $quiet < 1 );
find( { wanted => \&wanted_matches }, $search_path );
if ( !%found_files ) {
    print "No matches found!\n" if ( $quiet < 1 );
}

#the secondary search will only trigger if there are found matches and --ctime allows for it
my %ctime_matches; #hash of files that have close ctimes, key=filepath value=ctime matched
if ( $search_ctime && %found_files ) {
    print "Searching for similar change times...\n" if ( $quiet < 1 );
    find( { wanted => \&wanted_ctimes }, $search_path );
}

print "All searches complete.\n" if ( $quiet < 1 );



###################################################################################################
### output results
###################################################################################################

#print the list of matching files unless -qq (or -qqq)
if ( %found_files ) {
    my @found_files;

    print "The following files matched a malicious signature:\n" if ( $quiet < 1 );
    foreach my $file_name ( sort keys %found_files ) {
        $file_name =~ s/^\/vz\/root\/\d+// if ( $x_vzroot );
        print "$file_name\n" if ( $quiet < 2 );
        push @found_files, $file_name;
    }

    $data{'matches'} = {};
    $data{'matches'}{'count'} = scalar(@found_files);
    $data{'matches'}{'files'} = \@found_files;
}

#since skipped directories isn't a main function, this can be skipped with -q
if ( @skipped_dirs ) {
    my @skipped_dirs;
    print "\nThe following directories were skipped during this search:\n" if ( $quiet < 1 );
    foreach my $dir_name ( @skipped_dirs ) {
        print "$dir_name\n" if ( $quiet < 1 );
        push @skipped_dirs, $dir_name;
    }

    $data{'skipped'} = {};
    $data{'skipped'}{'count'} = scalar(@skipped_dirs);
    $data{'skipped'}{'dirs'} = \@skipped_dirs;
}

if ( @false_positives ) {
    print "\nThe following files are most likely false positives, and were skipped during " .
          "this search:\n" if ( $quiet < 1 );
    foreach my $false_pos ( @false_positives ) {
        print "$false_pos\n" if ( $quiet < 1 );
    }
}

if ( @skipped_files ) {
    print "\nThe following files match the listing in dirty_find_configs.yml and were skipped " .
          "during this search:\n" if ( $quiet < 1 );
    foreach my $file_name ( @skipped_files ) {
        print "$file_name\n" if ( $quiet < 1 );
    }
}

if ( @long_lines ) {
    print "\nThe following files contain lines longer than ${line_length} characters and were " .
          "skipped during this search:\n" if ( $quiet < 2 );
    foreach my $long_file ( @long_lines ) {
        print "$long_file\n" if ( $quiet < 2 );
    }
}

if ( @large_files ) {
    print "\nThe following files are larger than ${filesize} and were skipped during this " .
          "search:\n" if ( $quiet < 1 );
    foreach my $large_file ( @large_files ) {
        print "$large_file\n" if ( $quiet < 1 );
    }
}

###################################################################################################
### log results
###################################################################################################

#skipping log notifications requires -qqq ...not sure what it would be used for, but it's there
if ( $cust_log ) {
    open( FH, '>>', $cust_log );
    foreach my $file_name ( sort keys %found_files ) {
        $file_name =~ s/^\/vz\/root\/\d+//;  #need to do this either way for this log
        print FH "$file_name\n";
    }
    close( FH );
    print "\n\nCustomer log of above matches: $cust_log\n" if ( $quiet < 3 );

    if ( $search_ctime && %ctime_matches ) {
        ( my $ctime_cust_log = $cust_log ) =~ s/\.log$/_close-ctimes\.log/;
        open( FH, '>>', $ctime_cust_log );
        foreach my $file_name ( sort keys %ctime_matches ) {
            $file_name =~ s/^\/vz\/root\/\d+//;  #need to do this either way for this log
            print FH "$file_name\n";
        }
        close( FH );
        print "Customer log of similar ctimes: $ctime_cust_log\n" if ( $quiet < 3 );
    }

}

#admin logs contain both hash value and key so the results can be disected better
if ( $admin_log ) {

    my @ctimes;

    open( FH, '>>', $admin_log );
    foreach my $file_name ( sort keys %found_files ) {
        print FH "$found_files{ $file_name }: $file_name\n";
    }
    close( FH );
    print "\n\nAdmin log of above matches: $admin_log\n" if ( $quiet < 3 );

    if ( $search_ctime && %ctime_matches ) {
        ( my $ctime_admin_log = $admin_log ) =~ s/\.log$/_close-ctimes\.log/;
        open( FH, '>>', $ctime_admin_log );
        foreach my $file_name ( sort keys %ctime_matches ) {
            print FH "$ctime_matches{$file_name }: $file_name\n";
            push @ctimes, $file_name
        }
        close( FH );
        print "Admin log of similar ctimes: $ctime_admin_log\n" if ( $quiet < 3 );
    }

    $data{'ctimes'} = {};
    $data{'ctimes'}{'count'} = scalar(@ctimes);
    $data{'ctimes'}{'files'} = \@ctimes;
}


###################################################################################################
### subroutines
###################################################################################################


#simple wrapper on a few ENV commands to return 1 to ensure this is running only as a user w/ sudo
sub validate_sudo {
    #unfortunately, $< and $> don't do anything to distinguish root and sudo, so just grabbing ENV
    return 0 if ( $ENV{ USER } ne "root" );
    return 0 if (   ( $ENV{ SUDO_COMMAND } eq "/bin/su" )
                 || ( !( $ENV{ SUDO_USER } ) ) );
    return 1;
}

#to ensure all the log names share a 'timestamp', set based off a single usage of localtime
sub declare_logtime {
    my @timestamps  = localtime();
    my $set_logtime = ( $timestamps[4] + 1 )    . "-" .
                      ( $timestamps[3] )        . "-" .
                      ( $timestamps[5] - 100 )  . "_" .
                      ( $timestamps[2] )        .
                      ( $timestamps[1] )        .
                      ( $timestamps[0] );
    return $set_logtime;
}

sub declare_dir_limit {
    my $default   = shift;
    #if 0/disabled, manually set to MAX_LONG_INT without needing to use POSIX
    my $set_limit = ( !defined $limit ? $default
                    : ( $limit <= 0 ) ? 9223372036854775807
                    :                   $limit );
    return $set_limit;
}


#just a simple ( ? : ) declaration kept down here to keep the main body cleaner
sub declare_file_types {
    return qr/\.((p|s)?html|php|pl|js)\d*(\..*)?$/ if ( !defined $file_types );
    $file_types =~ s/,/|/g;
    return qr/\.($file_types)\d*(\..*)?$/;
}


#ensure that the customer log can be created and written to
sub create_cust_log {
    my $log_dir_path = shift;
    my $log_path     = "$log_dir_path/mt_scan_$logtime.log";
    return "" if ( !$cust_log_on );

    if ( -e $log_path ) {
        die "Customer log timestamp collision. Pleaes try re-running.\n";
    }

    # update data structure for log_path
    $data{'scans'}{'customer_log'} = $log_path;

    open( FH, '>', $log_path ) or die "Error opening customer log file.\n";
    close( FH ) or die "Error closing customer log file.\n";
    return $log_path;
}


#ensure that the admin log can be created and written to, the default path for this
#is /tmp/dirty_find, if that or any other /tmp/ path is used for admin logs this
#will create the path, but any other path with error and die if it doesn't exist for
#hopefully obvious sanity reasons
sub create_admin_log {
    my $log_path;
    if ( !defined $admin_log_on ) {
        return "";
    } elsif ( !$admin_log_on ) {
        my $log_dir = '/tmp/dirty_find';
        $log_path = $log_dir . "/dirty_find_$logtime.log";
        if ( -e $log_path ) {
            die "Admin log timestamp collision. Please try re-running.\n";
        } elsif ( !-e $log_dir ) {
            make_path($log_dir);
        }

        # update data structure for log_path
        $data{'scans'}{'admin_log'} = $log_path;

        open( FH, '>', $log_path ) or die "Error opening admin log file.\n";
        close( FH ) or die "Error closing admin log file.\n";
        return $log_path;
    } else {
        $admin_log_on =~ s/\/$//;
        $log_path     = "$admin_log_on/dirty_find_$logtime.log";
        if ( -e $log_path ) {
            die "Admin log timestamp collision. Please try re-running.\n";
        }
        if ( $admin_log_on =~ /^\/tmp\/[^\/]+/ ) {
            make_path( $admin_log_on );
        } elsif ( !( -e $admin_log_on ) ) {
            die "Provided path for admin logs does not exist.\n";
        }
        open( FH, '>', $log_path ) or die "Error opening admin log file.\n";
        close( FH ) or die "Error closing admin log file.\n";
        return $log_path;
    }
}


#simple binary return based on yes/no question
sub ask_yes_no {
    my $question = shift;
    print "$question y[es] or [n]o: ";
    my $input = <STDIN>;
    while ( $input !~ qr/y(es)?|no?/i ) {
        print "Please input y[es] or n[o]: ";
        $input = <STDIN>;
    }
    return 0 if ( $input =~ qr/no?/i );
    return 1;
}


#loop through web_roots and change any from 0755 to 0700 or vice versa
sub chmod_webroots {
    foreach my $file_name ( keys %found_files ) {
        foreach my $web_root ( keys %webroots ) {
            if ( $file_name =~ qr/^$web_root\// ) {
                $webroots{$web_root} = 1;
                last;
            }
        }
    }
    foreach my $web_root ( keys %webroots ) {
        my $perm = sprintf "%04o", ( stat( $web_root ) )[ 2 ] & 07777;
        if ( ( $webroots{$web_root} == 1 ) && ( $perm ne "0700" ) ) {
            if ( $force || ask_yes_no( "Matches in $web_root. Change perms to 0700?" ) ) {
                chmod 0700, $web_root;
                print "Permissions on $web_root changed to 0700.\n";
            }
        }
        if ( ( $webroots{$web_root} == 0 ) && ( $perm eq "0700" ) ) {
            if ( $force || ask_yes_no( "No matches in $web_root. Change perms to 0755?" ) ) {
                chmod 0755, $web_root;
                print "Permissions on $web_root changed to 0755.\n";
            }
        }
    }
}


#first find subroutine: will dig through files looking for signature matches
#only reason this is named this way is a nod to the documentation, the debug
#flag can be passed so that this will output the file and regex it is currently
#searching through for matches
sub wanted_matches {
    if ( -d ) {
        if ( ( stat( $_ ) )[7] > $dir_limit ) {
            push @skipped_dirs, $File::Find::name;
            $File::Find::prune = 1;
        }
        #proc directories create a lot of annoying races to open/read files
        if ( $_ eq 'proc' ) {
            $File::Find::prune = 1;
        }
    }

    if ( -f && ( $_ =~ $search_file_types ) ) {
        print "DEBUG: $File::Find::name " if ( $debug );
        my ( $p, $size ) = ( stat( $File::Find::name ) )[ 2, 7 ];
        my $perms        = sprintf "%04o", $p & 07777;
        if ( $perms == 6744 ) {
            print "$File::Find::name permissions set to 6744, chmodding to 0600.\n";
            chmod 0600, $File::Find::name;
        }
        # If the filehandle is too large we might get stuck
        if ( $size > $filesize ) {
            push @large_files, $File::Find::name;
            $File::Find::prune = 1;
            return;
        }
        elsif ( $size > $line_length ) {
            my $awk_lengths  = `awk '{print length(\$0)}' "$File::Find::name"`;
            my @line_lengths = split( "\n", $awk_lengths );
            foreach my $length ( @line_lengths ) {
                if ( $length > $line_length ) {
                    push @long_lines, $File::Find::name;
                    $File::Find::prune = 1;
                    return;
                }
            }
        }
        open( FH, $File::Find::name )
            or print "Can't open $File::Find::name -- this is concerning.\n" and return;
        local $/;
        my $file_slurp = <FH>;
        OUTER:
        foreach my $key ( keys %signatures ) {
            print "$key " if ( $debug );
            if ( $file_slurp =~ $signatures{ $key } ) {
                # Files like usage_201111.html are false positives
                if ( $File::Find::name =~ /usage_[0-9]{4,}\.html$/ ) {
                    push @false_positives, $File::Find::name;
                    $File::Find::prune = 1;
                    last;
                }
                foreach my $skip_file ( @$skip_files ) {
                    if ( $_ eq $skip_file ) {
                        push @skipped_files, $File::Find::name;
                        $File::Find::prune = 1;
                        last OUTER;
                    }
                }
                $found_files{ $File::Find::name } = $key;
                $found_ctimes{ ( stat( $_ ) )[10] } = 1;
                last;
            }
        }
        close( FH );
        print "\n" if ( $debug );
    }
}


#second find subroutine: go back through files to look for ctimes "close" to the
#list of files found from the previous subroutine
sub wanted_ctimes {
    if ( -d ) {
        if (   ( ( stat( $_ ) )[7] > $dir_limit )
            || ( $_ eq 'proc' )
            || ( $File::Find::name eq '/old' ) )
        {
            $File::Find::prune = 1;
        }
    }

    if ( -f && ( $_ =~ $search_file_types ) &&
       ( !( $found_files{ $File::Find::name } ) ) ) {
        my $file_ctime = ( stat( $_ ) )[10];
        foreach my $ts ( keys %found_ctimes ) {
            if ( ( $file_ctime <= $ts + $search_ctime ) && ( $file_ctime >= $ts - $search_ctime ) ) {
                $ctime_matches{ $File::Find::name } = $file_ctime;

            }
        }
    }

}

# track changes in json document
sub tracking {
  my $filename = "${scan_root}/tracker.json";
  my $json_text;
  my $obj;
  my $fh;

  # re-use old data from json docoument (when it exists)
  if ( -f $filename ) {
    open $fh, '<', $filename;
    flock $fh, 1; # shared lock
    $json_text = <$fh>;
    # set current data object with the value from the local
    # flat file json document
    $obj = decode_json($json_text);
    $data{'scans'}{'count'} = $obj->{'scans'}{'count'};
    $data{'scans'}{'dates'} = $obj->{'scans'}{'dates'};
    close($fh);
  }

  # add date onto array match
  push $data{'scans'}{'dates'}, $date;
  my $current_count = $data{'scans'}{'count'};
  my $new_count = $current_count + 1;
  $data{'scans'}{'count'} = $new_count;

  # JSON output
  # should sub this into an option
  # or dump to couchdb
  my $json_db = encode_json \%data;
  open $fh, ">", $filename or die("Could not open file. $!");
  flock $fh, 2; # exclusive lock
  print $fh $json_db;
  close $fh;
}


#the help menu...just using a print so i have total control over spacing
sub help_menu {
    print "

    dirty_find.pl [-p <path>] [-t <seconds>] [-l <directory_size>]
        [-f <.xxx,.yyy,.zzz>] [-c] [-a] [-d[d] [--force]] [-q[q[q]]] [-x] | [-h]

    Scan the specified path (or pwd if none) for files that match known malicious
    signatures. Currently, this is required to be run as a user via sudo. Options are as
    follows:

    -p|--path <path>
        Can be used to scan any specific path (even a single file).

    -t|--ctime <seconds>
        In addition to scanning for matching signatures, a second scan is performed to find
        any files with ctimes within <seconds> from any of the files matching a signature.
        This is to make it easier to identify files that were missed and/or larger trends.
        This feature is really only useful when logging the results, as it does not output
        to the screen. The default value is 3 seconds. To disable entirely, set to 0.

    -l|--limit <directory_size>
        By default, when using the path flag, this limit is disabled. It can still be 
        explicitly set with this flag.

    -n|--length <file_line_length>
        By default lines in all files are limited to 300,000 bytes, as anything higher can
        causes the regex matching to choke. Files containing lines of this length are
        printed at the end of the scan noting that they were skipped. This option allows
        you to specify a lower or higher limit for this, in bytes.

    -z|--size <file_size>
        By default files greater than 100,000,000 bytes (100MB) are skipped and printed
        at the end of the scan noting that they were skipped. This option allows you to
        specify a higher or lower limit for this.

    -f|--file_types <.xxx,.yyy,.zzz>
        By default, this will search all .php, .html, .js, and .pl files (including version
        numbers like .php5). If you wish to search a specific list of files, pass them to
        this flag as a comma separated list (example: -f .php,.pl). If you wish to scan all
        file types, pass .* instead.

    -a|--admin-logs [/path/to/dir]
        This will create log files that record both files/ctimes that matched as well as
        what signature/ctime they matched. This is more for administrative use. This flag
        has an optional argument if you want to specify which directory the logs are saved
        in. If omitted, this will default to /tmp/. This will only attempt to create
        the directory for logs if it exists within /tmp for sanity purposes.

    -q|--quiet
        This flag may be used once, twice, or three times, to supress various levels of
        output that is sent to the screen by default. Once will supress generic messages
        and status updates. Twice will additionally supress the list of matches (as it
        can sometimes be quite lengthy). Three times will supress all output including
        any notes letting the user know which logs have been created.

    -T|--tracking
        The tracking flag will create a small JSON document that stores the list of files
        that match compromised signatures and provides a count.  The same goes for skipped
        files and ctime files.  The idea is to have a standard serialization format of the
        data and simply track the number of scans done and the latest abuse matches.  It
        does NOT track the files historically, only the list of matches for the current
        can will be stored.  Historical values are scan counts and the dates of scans.

    -h|--help
        This help menu!
    ";

    exit;
}

# gather signature matches / skip files from yaml config
sub generate_configs {
    # currently gathers a set of arrays signature matches
    # from configs.yml file... then loops them into
    # a hash to accomodate original model.
    my %sigs;

    my $confile = LoadFile('/opt/mt/etc/dirty_find_configs.yml');

    my %matches = %{ $confile->{'matches'} };

    # return regex quoted
    # http://perldoc.perl.org/functions/qr.html
    foreach my $sig ( keys %matches ) {
        $sigs{$sig} = qr/$matches{$sig}/x;
    }

    my $skips = $confile->{'skips'};

    return ( \%sigs, $skips );
}
