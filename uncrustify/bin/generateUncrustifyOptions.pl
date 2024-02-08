#!/usr/bin/perl

use v5.36;
use strict;

use Getopt::Long;
use FindBin qw($Bin $Script);
use lib "$Bin/.";

### Global variables used by this script and the module UDocTools
our $verbose = 0;  # set by user on command line
our $ucBin;        # set by user on command line (default is $Bin)

use UDocTools qw(loadOptionDescriptions getOption SayError Fatal dumpit slurpFile);

# Script name  (without the .pl) used in the error messages
$Script =~ s/^(.+)\.pl$/$1/i;

##
## main
##
#
# The default layout is
#    base/
#     +->uds/                   <-- inputDir
#     |   +-> *.uds             <-- uds file edited manually
#     |   +->default/
#     |       +->*.uds          <-- uds file autogenerated
#     +->options/               <-- outputDir
#     |   +-> *.html
#     |
#     +->static/                <-- defined as ./options/../static
#         +--> html, png...     <-- static files uses in the html
#

$|=1;
my $binDir    =  $Bin;                 # where to find the uncrustify binary
my $inputDir  = "$Bin/../uds";         # where to find the uds files
my $outputDir = "$Bin/../options";     # where to generate the html files
my $forceHtml = 0;                     # force html generation regardless of its date
my $inputFile;                         # generate the html using this input .uds

my %categories;  # a hash of array  Used to sort options by category
my %types;       # a hash of array  User to sort options by type

GetOptions (
  "bindir=s"     => \$binDir,    # string
  "inputdir=s"   => \$inputDir,  # string
  "outputdir=s"  => \$outputDir, # string
  "verbose"      => \$verbose    # flag
) or Fatal("Invalid command line arguments");

$binDir .= '/'  if $binDir && $binDir !~ m(/$);
$ucBin   = "${binDir}uncrustify.exe";

my $err=0;
if( $binDir ){
    if( ! -d $binDir ){
        Error("Path --bindir $binDir doesn't exist.");
        $err++;
    }elsif( ! -e $ucBin ){
        Error("Uncrustify binary $ucBin doesn't exist.");
        $err++;
    }
}else{
    Error("Path --bindir is not defined.");
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
        Error("Path --outputdir $outputDir doesn't exist.");
        $err++;
    }
}else{
    Error("Path --outputDir is not defined.");
    $err++;
}

exit(3) if $err;

##
## 1) Collect the information from uncrustify
##

my $ucVersion = getOption('--version');
$ucVersion = (split('-', $ucVersion))[1];

my $options = loadOptionDescriptions();

my $fname = "$outputDir/SUMMARY.txt";
open(my $fh, '>', $fname)
  || Fatal("Can't create summary $fname:\n$!");
print $fh dumpit($options);
close($fh);
my $optCount = (keys %{$options}) - 1;  # the [header] section is not a real option
print "\n$optCount options + 'header' wrote in summary: $fname\n";

##
## 2) Generate an htm page for each option
##    and collected information for indexes
##

## Parse 'header'
my @Categories = split('\|', $options->{header}{categories}||'');

## Parse each option
for my $optKey (sort keys %{$options}){
    next if $optKey eq 'header';

    my $optHtmlFile = "$outputDir/$optKey.html";
    open(my $fh, '>', $optHtmlFile)
      || Fatal("Can't save option in $optHtmlFile:\n$!");

    ### html header
    print($fh join("\n",
                '<!doctype html>',
                '<html>',
                '<head>',
                '  <meta charset="utf-8">',
                "  <title>$optKey - uncrustify options</title>",
                '  <link rel="stylesheet" href="../static/uncrustify.css">',
                '  <link rel="stylesheet" href="../static/ins_tooltip.css">',
                '</head>',
                '<body>'
              ), "\n");

    ### name of the option as used in the config file: Example: indent_func_call_param
    printf($fh qq{<h1><pre style="color:yellow">%s</pre></h1>\n}, $optKey);

    my $option = $options->{$optKey};
    delete $option->{CallName};

    ### PROPERTIES
    printf($fh "\n<h1>Properties</h1>\n<pre>\n");
    my $type    = delete $option->{EditorType};
    my $default = delete $option->{ValueDefault};
    my $expected="unknown";
    if( $type eq 'boolean' ){
        $expected="[false, true]";
        delete $option->{TrueFalse};
    }elsif( $type eq 'numeric' ){
        # NOTE: there are 10 options with not value for MaxVal anf MinVal
        my $max = delete $option->{MaxVal};
        my $min = delete $option->{MinVal};
        $min = $default if $min eq '';
        $expected="[$min .. $max]";
    }elsif( $type eq 'string' ){
        $expected="";
    }elsif( $type eq 'multiple' ){
        delete $option->{ChoicesReadable};
        my $choices = delete $option->{Choices};
        $choices =~ s!^"(.*)"$!$1!;  # cleanup only required by 'indent_with_tabs'
        my @choices = map {/(\w+)$/; $1} split('\|', $choices);
        $expected="(@choices)";
    }else{
        Warning("Unexpected value '$type' for field 'EditorType' in option '$optKey'");
    }

    my $catName = $Categories[$option->{Category}]||'unknow';
    printf($fh "  Category: $catName\n");
    printf($fh "      Type: $type $expected\n");
    printf($fh "   Default: $default\n");
    delete $option->{Category};

    # update hashes used later to generate indexes
    $types{$type} ||= [];
    push(@{$types{$type}}, $optKey);
    $categories{$catName} ||= [];
    push(@{$categories{$catName}}, $optKey);

    # extract the description now (used later)
    my $desc = delete $option->{Description};

    # All options have Enabled=false, excepted 'indent_with_tabs'
    # What is the goal of this properties ?
    delete $option->{Enabled};

    # print unmanaged properties (empty list expected)
    if( 0 < keys %{$option} ){
        print($fh "Other properties\n");
        for my $prop (sort keys %{$option}){
            next if $prop =~ /^opt/;
            print($fh "  $prop: $option->{$prop}\n");
        }
    }

    # end of properties list
    printf($fh "</pre>\n");

    ### DESCRIPTION
    # remove quote and some html tags
    $desc =~ s!^"(.*)"$!$1!;
    $desc =~ s!<br/>!\n!g;
    $desc =~ s!</?html>!!g;
    printf($fh "<h1>Description</h1>\n<pre>\n%s\n</pre>\n", $desc);

    ### EXAMPLE
    # generate the Example section based on the uds file
    # if $inputDir/$optKey.uds exists use it, else use $inputDir/default/$optKey.uds
    print($fh "<h1>Examples</h1>\n");
    my $udsFile = "$optKey.uds";
    my $udsDefault = "$inputDir/default/$udsFile";
    $udsFile = "$inputDir/$udsFile";
    $udsFile = $udsDefault unless -f $udsFile;
    my $html = -f $udsFile ? UdsFile2Html($udsFile)
                           : slurpFile("$outputDir/../static/missing_uds.html");
    $html = slurpFile("$outputDir/../static/invalid_uds.html") unless $html;
    print $fh $html;

    ### NOTES
    print($fh "<h3>Notes</h3><ul>\n");
    print($fh qq{<li> Report problems related to this documentation <a href="https://github.com/JEAYNE/jeayne.github.io/issues" target="_blank">here</a>.\n});
    print($fh qq{<li> This documentation project is <b>not</b> managed by the <a href="https://github.com/uncrustify" target="_blank">uncrustify</a> team.\n});
    print($fh "</ul>\n");

    ### close the html page
    print($fh "</body>\n</html>\n");
    close($fh);

}

##
## 3) Generate indexes
##

sub indexHeader {
    my $name = shift;
    my $howMany = shift || "once";
    return qq{
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <link rel="stylesheet" href="../static/uncrustify.css">
  <title>Uncrustify options by $name</title>
</head>
<body>
<div class="left_scroll">
  <a href="../index.html"><img src="../static/home-16.png"></a> | <a href="index_name.html">by name</a> | by <a href="index_category.html">category</a> | by <a href="index_type.html">type</a> | by <a href="index_keyword.html">keyword</a>
  <p>Uncrustify version $ucVersion &nbsp; by <font color="red">$name</font></p>
  <p><i>Each option appears $howMany in this index.</i></p>
  <dl>
}
}

sub indexFooter {
    my $name = shift;
    return qq{  </dl>
 <p align="center"><i>~ End of list by <font color="red">$name</font> ~</i></p>
</div>
<div class="right_display">
  <iframe src="../static/empty_frame.html" title="uncrustify option" name="option" style="border:none;height:100%;width:100%" ></iframe>
</div>
</body>
</html>
}
};

## Index by name
my %keywords;
my @allOptionsSorted = sort keys %{$options}; # To speed up

$fname="$outputDir/index_name.html";
open($fh, '>', $fname)
  || Fatal("Can't create index $fname:\n$!");
print($fh indexHeader('name','once'));
my $prefix = '';
for my $optKey (@allOptionsSorted){
    next if $optKey eq 'header';
    (my $pfix = $optKey) =~ s/^([^_]+).*$/$1/;
    if( $pfix ne $prefix ){
        $prefix = $pfix;
        print($fh qq{    <dt><b>$prefix</b>:</dt>\n});
    }
    print($fh qq{      <dd><a href="$optKey.html" target="option">$optKey</a></dd>\n});
    # update the keyword list
    $keywords{$_}++ for (split '_', $optKey);
}
print($fh indexFooter('name'));
close($fh);

## Index by category
$fname="$outputDir/index_category.html";
open($fh, '>', $fname)
  || Fatal("Can't create index $fname:\n$!");
print($fh indexHeader('category','once'));
for my $catName (sort keys %categories){
    print $fh qq{  <dt>$catName</dt>\n};
    for my $optKey (@{$categories{$catName}}){
        print($fh qq{      <dd><a href="$optKey.html" target="option">$optKey</a></dd>\n});
    }
}
print($fh indexFooter('category'));

## Index by type
$fname="$outputDir/index_type.html";
open($fh, '>', $fname)
  || Fatal("Can't create index $fname:\n$!");
print($fh indexHeader('type','once'));
for my $typeName (sort keys %types){
    print $fh qq{  <dt>$typeName</dt>\n};
    for my $optKey (@{$types{$typeName}}){
        print($fh qq{      <dd><a href="$optKey.html" target="option">$optKey</a></dd>\n});
    }
}
print($fh indexFooter('type'));

## Index by keyword
# remove some words that are not real keywords
delete $keywords{$_} for (qw(0 1 2 as at of only the to));

$fname="$outputDir/index_keyword.html";
open($fh, '>', $fname)
  || Fatal("Can't create index $fname:\n$!");
print($fh indexHeader('keyword', 'several times'));
for my $kw (sort keys %keywords){
    print $fh qq{  <dt>$kw</dt>\n};
    for my $optKey (@allOptionsSorted){
        next unless $optKey =~ /(\b|_)$kw(_|\b)/;
        print($fh qq{      <dd><a href="$optKey.html" target="option">$optKey</a></dd>\n});
    }
}
print($fh indexFooter('keyword'));

exit;

##
## functionx to load and convert uds to html
##

sub getUdsBlock {
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
    my $fh;
    unless( open($fh, '<', $udsFile) ){
        SayError("Cannot open uds file '$udsFile'\n$!");
        return;
    }

    my %uds = (
      path    => $udsFile,
    );

    (my $optKey = $udsFile) =~ s!^.*?([^/]+)\.uds$!$1!;
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
                $line = getUdsBlock($fh, \$uds{desc});
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
                $line = getUdsBlock($fh, \$uds{code});
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
                    next if $kv =~ /^\w+=[-\w]+$/;
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

sub UdsFile2Html {
    my $udsFile = shift;   # input file
    my $uds = loadUDS($udsFile);  # return ref to a hash, undef if error.
    return unless $uds;

    my $tmpFile = ($ENV{TMP} || $ENV{TEMP}) . "/uncrustify.tmp";
    open(my $tmp_fh, ">", $tmpFile)
      || Fatal("Cannot create tmp file $tmpFile\n$!");
    print $tmp_fh $uds->{code};
    close($tmp_fh);

    my %results;
    for my $set (@{$uds->{set}}){
        # build the list --set opt1Name=opt1Value --set opt2Name=opt2Value ...
        my $setList = '--set indent_with_tabs=0 --set indent_columns=4 '
                    . join(' ', map("--set $_", split(/\s+/, $set)));
        my $cmd = "$ucBin -c - $setList -l $uds->{lang} -f $tmpFile";
        say "== Running uncrustify $set";
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

    return join "\n", "<pre>$uds->{desc}</pre>"
                    , "<table><tr>"
                    , "$tblHeader</tr><tr>"
                    , "$tblBody</tr></table>\n";
}

__END__
