#!/usr/bin/perl

use v5.36;
use strict;

use Getopt::Long;
use FindBin qw($Bin $Script);
use lib "$Bin/.";

### Global variables used by this script and the module UDocTools
our $verbose = 0;  # set by user on command line
our $ucBin;        # set by user on command line (default is $Bin)

use UDocTools qw(getOption SayError Fatal dumpit);

### Global variables used by this script
$|=1;
my $binDir    =  $Bin;                 # where to find the uncrustify binary
my $inputDir  = "$Bin/../uds/default"; # where to find the default .uds (Uncrustify Documentation Script) files
my $outputDir = "$Bin/../examples";    # where to generate the html files
my $forceHtml = 0;                     # force html generation regardless of its date
my $inputFile;                         # generate the html using this input .uds

# $inputFile = "$Bin/../uds/indent_braces.uds";  #### DEBUG !!!

#
# The expected file layout is
#    base/
#     +->uds/
#     |   +-> *.uds             <-- inputDir/..  (tuned uds hidding version in inputDir)
#     |   +->default
#     |       +->*.uds          <-- inputDir     (auto generated uds)
#     +->examples               <-- outputDir
#     |    +-> *.ex.html
#     +->options
#          +-> *.html
#

# Nom du script (sans .pl) utilisé dans les messages d'erreur
$Script =~ s/^(.+)\.pl$/$1/i;

# ==== NAME the_option_name
#
# ==== INPUT: CPP
#
# void main(int argc, char** argv){
#   putc("Hello !");
# }
# ==== SET: the_option_name=ignore
#
# ==== SET: the_option_name=force
#
# ==== TRACK: space

sub getBlock {
    my $FH        = shift;
    my $refResult = shift;
    my $str = '';
    my $line;
    while( $line = <$FH> ){
        last if $line =~ /^={4,}/;
        $str .= $line;
    }
    ${$refResult} = ($str =~ /^\s*$/) ? '' : $str;
    return $line;
}

sub loadUDS {
    my $udsFile = shift;
    (my $optKey = $udsFile) =~ s!^.*?([^/]+)\.uds$!$1!;
    say "Option $optKey from $udsFile";

    open(my $fh, '<', $udsFile)
      || Fatal("Cannot open uds file '$udsFile'\n$!");

    my %uds = (
      path    => $udsFile,
    );

    my $line;
    while( $line = <$fh> ){
        chomp $line;
        next if $line =~ /^\s*(#.*)?$/;
        if( $line =~ /^={4,}\s*([A-Z]+)\s*(:\s*)?(.*?)(\s*)$/ ){
            my $action=$1;
            my $param=$3;
            if( $action eq 'INFO' ){
                ; # nothing to do.
            }elsif( $action eq 'NAME'  ){
                # This is a double check to be sure that the name of the file and its contain are inline.
                # Example: '==== NAME: align_func_params'
                if( $param ne $optKey ){
                    SayError("Name '$param' doesn't match with '$optKey' in uds file name: $udsFile");
                    return;
                }
                $uds{optKey}=$optKey;
                # optional block description
                $line = getBlock($fh, \$uds{desc});
                $line ? redo : last;
            }elsif( $action eq 'CODE' ){
                # Example: '==== CODE: C++'
                my $lang = uc($param||'CPP');
                $lang = "CPP" if $lang eq 'C++';
                $lang = "CS"  if $lang eq 'C#';
                if( $lang !~ /^(C|CPP|D|CS|JAVA|PAWN|OC|OC+|VALA)$/ ){
                    SayError("'$param' is un invalid language in uds file '$udsFile'");
                    return;
                }
                $uds{lang} = $lang;
                # mandatory block of code
                $line = getBlock($fh, \$uds{code});
                unless( $uds{code} ){
                    SayError("'CODE' is empty in uds file '$udsFile'");
                    return;
                }
                $line ? redo : last;
            }elsif( $action eq 'SET'  ){
                # Example: '==== SET align_func_params=false align_keep_tabs=false'
                # Check that $param is a list of 'key=value'
                if( $param =~ /^\s*$/ ){
                    SayError("Empty SET in uds file '$udsFile'");
                    return;
                }
                for my $kv ( split(/\s+/, $param) ){
                    next if $kv =~ /^\w+=\w+$/;
                    SayError("Invalid SET '$kv' in uds file '$udsFile'");
                    return;
                }
                push(@{$uds{set}}, $param);
            }elsif( $action eq 'TRACK' ){
                if( $param !~ /^(nl|space|start)$/ ){
                    SayError("'$param' is an invalid tracking mode in uds file '$udsFile'");
                    return;
                }
                push @{$uds{tracking}}, $param;
            }else{
                SayError("'==== $action' is not a valid action in uds file '$udsFile'");
                return;
            }
        }else{
            SayError("Invalid line: '$line' in uds file '$udsFile'");
            return;
        }
    }
    close($fh);

    my $errMsg = '';
    $errMsg .= "  '==== NAME' is missing\n" unless $uds{optKey};
    $errMsg .= "  '==== CODE' is missing\n" unless $uds{code};
    $errMsg .= "  '==== SET'  is missing\n" unless $uds{set};
    if( $errMsg ){
        SayError( "Missing section in '$udsFile':\n$errMsg\n");
        return;
    }
    
    # cleanup
    $uds{code} =~ s/\s+$/\n/;

    return \%uds;
}


sub execUDS {
    my $udsFile  = shift;   # input file
    my $htmlFile = shift;   # output file
    my $uds = loadUDS($udsFile);  # return ref to a hash, undef if error.
    return unless $uds;

    my $tmpFile = ($ENV{TMP} || $ENV{TEMP}) . "/uncrustify.tmp";
    open(my $tmp_fh, ">", $tmpFile)
      || Fatal("Cannot create tmp file $tmpFile\n$!");
    print $tmp_fh $uds->{code};
    close($tmp_fh);

    my %results;
    for my $set (@{$uds->{set}}){
        # build the list --set opt1Name=opt1Value --set opt2Name=opt2Value
        my $setList = '--set indent_with_tabs=0 --set indent_columns=4 '
                    . join(' ', map("--set $_", split(/\s+/, $set)));
        my $cmd = "$ucBin -c - $setList -l $uds->{lang} -f $tmpFile";
        my $result;
        if( open(my $pipe, "$cmd |") ){
            my $line;
            while($line=<$pipe>){
                $result .= $line;
            }
            close($pipe);
            $results{$set} = $result || "ERROR executing pipe '$cmd | ...'";
        }else{
            SayError("Cannot execute pipe '$cmd | ...'\n$!");
        }
    }

    my $optKey = $uds->{optKey};

    ## In description substitute `xx` by
    ## <ins class="xx" alt="optKey"></ins>
    $uds->{desc} =~ s!`(\w+)`!<ins class="$1" alt="$optKey"></ins>!g;

    # Generate the table 
    #   | raw code | option_name=value1 | option_name=value2 | 
    #   +----------+--------------------+--------------------+
    #   |  code    | result             | result             |
    #   +----------+--------------------+--------------------+

    my $tblHeader = qq(  <th>raw code</th>\n);
    my $tblBody   = qq(<td class="code">$uds->{code}</td>\n);
    for my $set (@{$uds->{set}}){  # To preserve original order do not use (sort keys %results)
        $set =~ s!\s+!<br/>!g;
        $tblHeader .= qq(  <th>$set</th>\n);
        $tblBody   .= qq(<td class="code">$results{$set}</td>\n);
    }

    ##  generate the html file <optKey>.ex.html
    say "Writting $htmlFile";
    open(my $html_fh, '>', $htmlFile)
      || Fatal("Cannot create -ex.html file $htmlFile\n$!");

    print $html_fh qq{
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Example for $optKey</title>
  <link rel="stylesheet" href="../static/uncrustify.css">
  <link rel="stylesheet" href="../static/ins_tooltip.css">
</head>
<body>
<pre>
$uds->{desc}
</pre>
<table><tr>
$tblHeader
</tr><tr>
$tblBody
</tr></table>
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
        SayError("Path --bindir $binDir doesn't exist.");
        $err++;
    }elsif( ! -e $ucBin ){
        SayError("Uncrustify binary $ucBin doesn't exist.");
        $err++;
    }
}else{
    SayError("Path --bindir is not defined.");
    $err++;
}

if( $inputDir ){
    if( ! -d $inputDir ){
        Error("Path --inputdir '$inputDir' doesn't exist.");
        $err++;
    }
}else{
    Error("Path --inputDir is not defined.");
    $err++;
}

if( $outputDir ){
    if( ! -d $outputDir ){
        SayError("Path --outputdir $outputDir doesn't exist.");
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
   next unless $file =~ /^(.+)\.uds$/;
   my $optKey = $1;
   my $udsFile = "$inputDir/$file";
   next unless -f $udsFile;
   # If this file also exist in the parent directory use it.
   my $udsParentFile = "$inputDir/../$file";
   $udsFile = $udsParentFile if -f $udsParentFile;
   # Do nothing if corresponding html file is younger
   my $htmlFile = "$outputDir/$optKey.ex.html";
   if( (! -f $htmlFile) || $forceHtml || ((stat($htmlFile))[9] < (stat($udsFile))[9]) ){
       execUDS($udsFile, $htmlFile);
   }else{
       say "$file.ex.html is already uptodate";
   }
}

close($dh);

__END__
