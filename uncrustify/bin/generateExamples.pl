#!/usr/bin/perl

use v5.36;
use strict;

use Getopt::Long;
use FindBin qw($Bin $Script);
use lib "$Bin/.";

### Global variables used by this script and the module UDocTools
our $verbose = 0;  # set by user on command line 
our $ucBin;        # set by user on command line (default is $Bin)

use UDocTools qw(getOption SayError Fatal);

### Global variables used by this script
$|=1;
my $binDir    =  $Bin;                 # where to find the uncrustify binary
my $inputDir  = "$Bin/../uds/default"; # where to find the default .uds (Uncrustify Documentation Script) files
my $outputDir = "$Bin/../examples";    # where to generate the html files
my $forceHtml = 0;                     # force html generation regardless of its date
my $inputFile;                         # generate the html using this input .uds

$inputFile = "$Bin/../uds/indent_braces.uds";  #### DEBUG !!!

#
# The expected file layout is
#    base/
#     +->uds/
#        +-> *.uds             <-- inputDir/..  (tuned uds hidding version in inputDir)
#        +->default
#            +->*.uds          <-- inputDir     (auto generated uds)
#


# Nom du script (sans .pl) utilisé dans les messages d'erreur
$Script =~ s/^(.+)\.pl$/$1/i;

# ==== NAME the_option_name
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

    open(my $fh, '<', $path)
      || Fatal("Cannot open file '$path'\n$!");

    my $line;
    while($line = <$fh>){
        next unless $line =~ /^={4,}\s+(NAME)(:|\s)\s*(?<optName>\S+)/;
        last if $+{optName} eq $optName;
        SayError("Name '$+{optName}' doesn't match with '$optName' in file name: $path");
        return;
    }

    my $lang;
    my $comment = '';
    while($line = <$fh>){
        if( $line =~ /^={4,}\s*INPUT((:|\s)\s*(?<lang>\S+))?/ ){
            $lang = uc($+{lang}||'') || "CPP";   # C, CPP, CS, D, JAVA, OC, OC+, PAWN, VALA.
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
        SayError("No input defined in $path");
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
        SayError("No value defined for option $optName in $path");
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
            SayError("Cannot execute pipe '$cmd | ...'");
        }
    }
    for my $optValue (sort keys %results){
        print "==== $optValue\n";
        print $results{$optValue};
    }

    ## In comment substitute `xx` by
    ## <ins class="xx" alt="optName"></ins>
    $comment =~ s!`(\w+)`!<ins class="$1" alt="$optName"></ins>!g;

    ##  generate the <optName>.ex.html file
    my $htmlFile = "$outputDir/$optName.ex.html";
    open(my $html_fh, '>', $htmlFile)
      || Fatal("Cannot create -ex.html file $htmlFile\n$!");

    print $html_fh qq{
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Example for $optName</title>
  <link rel="stylesheet" href="../static/uncrustify.css">
  <link rel="stylesheet" href="../static/ins_tooltip.css">
</head>
<body>
<pre>
$comment
</pre>
<table><tr>
};

    # The header of each column
    print $html_fh "  <th>not formated</th>\n";
    for my $optValue (keys %results){
        print $html_fh "  <th>$optValue</th>\n";
    }

    # First column: code not formated
    print $html_fh qq{</tr><tr><td class="code">\n}, $input;

    # the various formated versions
    for my $optValue (keys %results){
    print $html_fh qq{</td><td class="code">\n}, $results{$optValue};
    }

    # footer
    print $html_fh qq{
</td></tr>
</table>
</body>
</html>
    };

    close($html_fh);
}


##
## main
##

GetOptions (
  "bindir=s"     => \$binDir,    # string
  "force"        => \$forceHtml, # flag
  "inputdir=s"   => \$inputDir,  # string
  "inputfile=s"  => \$inputFile, # string
  "outputdir=s"  => \$outputDir, # string
  "verbose"      => \$verbose    # flag
) or Fatal("Invalid command line arguments");

$binDir .= '/'  if $binDir && $binDir !~ m(/$);
$ucBin  = "${binDir}uncrustify.exe";

my $err=0;
if( $binDir ){
    if( ! -d $binDir ){
        SayError("Path '$binDir' doesn't exist.");
        $err++;
    }elsif( ! -e $ucBin ){
        SayError("File '$ucBin' doesn't exist.");
        $err++;
    }
}else{
    SayError("Path --bindir is not defined.");
    $err++;    
}

if( $outputDir ){
    if( ! -d $outputDir ){
        SayError("Path '$outputDir' doesn't exist.");
        $err++;
    }
}else{
    SayError("Path --outputDir is not defined.");
    $err++;
}

exit(3) if $err;

my $ucVersion = getOption('--version');
$ucVersion = (split('-', $ucVersion))[1];
say "Using Uncrustify version $ucVersion";

if( $inputFile ){
    unless( -f $inputFile ){
        SayError("The --inputfile '$inputFile' doesn't exist");
    }
    execUDS($inputFile);
    exit;
}

# read each uds file
# ignore the file if the output/html is younger than input/uds
opendir(my $dh, $inputDir)
  || Fatal("Could not open '$inputDir' for reading\n$!");

while( my $file = readdir($dh) ){
   next if $file =~ /^\./;
   my $udsPath = "$inputDir/$file";
   next unless -f $udsPath;
   next unless $udsPath =~ /\.uds$/;
   # If this file also exist in the parent directory use it.
   my $udsParentPath = "$inputDir/../$file";
   $udsPath = $udsParentPath if -f $udsParentPath;
   # Do nothing if corresponding html file is younger
   my $htmlPath = "$outputDir/$file.ex.html";
   if( $forceHtml || ((stat($htmlPath))[9] < (stat($udsPath))[9]) ){
       execUDS($udsPath);
   }else{
       say "$file.exe.html is already uptodate";
   }

}

close($dh);

__END__
