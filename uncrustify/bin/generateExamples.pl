#!/usr/bin/perl

use warnings;
use strict;

use Getopt::Long;
use Data::Dumper;

# global variables
(my $myName = $0) =~ s!^.*?([^/\\]+)$!$1!;
my $verbose = 0;
my $binDir  = '.'; # where to find the uncrustify binary (default: current dir)
my $ucBin   = '';
my $inputDir;      # where to find the .uds (Uncrustify Documentation Script) files
my $outputDir;     # where to generate the html files

sub Debug {
    $verbose && print "\e[94m", shift, "\e[0m\n";
}

sub Info {
    print "\e[92m", shift, "\e[0m\n";
}

sub Warning {
    print STDERR "$myName\e[93m WARNING: ", shift, "\e[0m\n";
}

sub Error {
    print STDERR "$myName\e[91m ERROR: ", shift, "\e[0m\n";
}

sub Fatal {
    print STDERR "$myName\e[91m ERROR: ", shift, "\e[0m\n";
    die "\n";
}

# routine used to check the path, and get the version
sub getOption {
  my $option = shift || '';
  open(PIPE, '-|', $ucBin, $option)
    || Fatal("Can't exec '$ucBin'\n$!");
  my $result=<PIPE>;
  close(PIPE);
  chomp($result);
  return $result;
}

# ==== NAME
# bla bla ...
# bla ...
#
# ==== INPUT: CPP
#
# void main(int argc, char** argv){
#   putc("Hello !");
# }
#
# ==== WITH: ignore
#
# ==== WITH: force

sub execUDS {
    my $path = shift;
    (my $optName = $path) =~ s!^.*?([^/]+)\.uds$!$1!;
    print "Option $optName from $path\n";

    open(my $fh, $path)
      || Fatal("Cannot open file '$path'\n$!");

    my $line;
    while($line = <$fh>){
        next unless $line =~ /^={4,}\s+(NAME)(:|\s)\s*(?<optName>\S+)/;
        last if $+{optName} eq $optName;
        Error("Name '$+{optName}' doesn't match with '$optName' in file name: $path");
        return;
    }

    my $lang;
    my $comment = '';
    while($line = <$fh>){
        if( $line =~ /^={4,}\s*INPUT((:|\s)\s*(?<lang>\S+))?/ ){
            $lang = uc($+{lang}) || "CPP";   # C, CPP, CS, D, JAVA, OC, OC+, PAWN, VALA.
            $lang = "CPP" if $lang eq 'C++';
            $lang = "CS"  if $lang eq 'C#';
            last;
        }
        $comment .= $line;
    }

    my $input;
    while($line = <$fh>){
        last if $line =~ /^={4,}\s*WITH/;
        $input .= $line;
    }
    unless( $input ){
        Error("No input defined in $path");
        return;
    }
    my $tmpFile = "$outputDir/tmpinput.tmp";
    open(my $tmp_fh, ">", $tmpFile)
      || Fatal("Cannot create tmp file $tmpFile\n$!");
    print $tmp_fh $input;
    close($tmp_fh);

    my @params;
    do {
        push(@params, $+{optVal}) if $line =~ /^={4,}\s*WITH(:|\s)\s*(?<optVal>\w+)/;
    } while($line = <$fh>);

    unless( @params ){
        Error("No value defined for option $optName in $path");
        return;
    }

    close($fh);

    print "--- Comment ---\n";
    print $comment;
    print "--- Input ($lang) ---\n";
    print $input;
    print "---- Run ----\n";
    my %results;
    for my $optValue (@params){
        my $cmd = "$ucBin -c - --set $optName=$optValue -l $lang -f $tmpFile";
        my $result; 
        if( open(my $pipe, "$cmd |") ){
            while($line=<$pipe>){
                $result .= $line;
            }
            close($pipe);
            $results{$optValue} = $result || "ERROR executing pipe '$cmd | ...'";
        }else{
            Error("Cannot execute pipe '$cmd | ...'");
        }
    }
    for my $optValue (sort keys %results){
        print "==== $optValue\n";
        print $results{$optValue};
    }
    
    ## TBD: generate the html file
}


##
## main
##
$|=1;

GetOptions (
  "bindir=s"     => \$binDir,    # string
  "inputdir=s"   => \$inputDir,  # string
  "outputdir=s"  => \$outputDir, # string
  "verbose"      => \$verbose    # flag
) or Fatal("Invalid command line arguments");

$binDir = $1 if $binDir =~ m!^(.+)/+$!;
$ucBin  = "${binDir}/uncrustify.exe";

my $err=0;
if( $binDir  && ! -d $binDir ){
    Error("Path '$binDir' doesn't exist.");
    $err++;
}elsif( ! -e $ucBin ){
    Error("File '$ucBin' doesn't exist.");
    $err++;
}

if( $inputDir ){
    $inputDir = $1 if $inputDir =~ m!^(.+)/+$!;
    if( ! -d $inputDir ){
        Error("Path '$inputDir' doesn't exist.");
        $err++;
    }
}else{
    Error("--inputDir not set.");
    $err++;
}

if( $outputDir ){
    $outputDir = $1 if $outputDir =~ m!^(.+)/+$!;
    if( ! -d $outputDir ){
        Error("Path '$outputDir' doesn't exist.");
        $err++;
    }
}else{
    Error("--outputDir not set.");
    $err++;
}

exit(3) if $err;

# read each uds file
# ignore the file if the output/html is younger than input/uds
opendir(my $dh, $inputDir)
  || Fatal("Could not open '$inputDir' for reading\n$!");

while( my $file = readdir($dh) ){
   next if $file =~ /^\./;
   my $path = "$inputDir/$file";
   next unless -f $path;
   next unless $path =~ /\.uds$/;
   execUDS($path);
}

close($dh);

__END__
