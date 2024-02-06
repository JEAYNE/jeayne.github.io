#!/usr/bin/perl

use v5.36;
use strict;

use Getopt::Long;
use FindBin qw($Bin $Script);
use lib "$Bin/.";

### Global variables used by this script and the module UDocTools
our $verbose = 0;  # set by user on command line
our $ucBin;        # set by user on command line (default is $Bin)

use UDocTools qw(loadOptionDescriptions getOption SayError Fatal dumpit);

# Nom du script (sans .pl) utilisé dans les messages d'erreur
$Script =~ s/^(.+)\.pl$/$1/i;

##
## main
##

$|=1;
my $binDir    =  $Bin;                 # where to find the uncrustify binary
my $inputDir  = "$Bin/../examples";    # where to find the examples
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
my $optCount = (keys %{$options}) - 1;  # the [header] section is not an option.
print "\n$optCount options + 'header' wrote in summary: $fname\n";

##
## 2) Generate a page for each options
##    and collected information for indexes
##

## Parse headers
my @Categories = split('\|', $options->{header}{categories}||'');

## Save
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

    ### name of the option as used in the config file
    printf($fh qq{<h1><pre style="color:yellow">%s</pre></h1>\n}, $optKey);

    my $option = $options->{$optKey};
    delete $option->{CallName};

    ### properties
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

    # update hashes used later to generated indexes
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

    ### Description
    # remove quote and some html tags
    $desc =~ s!^"(.*)"$!$1!;
    $desc =~ s!<br/>!\n!g;
    $desc =~ s!</?html>!!g;
    printf($fh "<h1>Description</h1>\n<pre>\n%s\n</pre>\n", $desc);

    ### Examples (if any)
    print($fh "<h1>Examples</h1>\n");
    my $exFile = "$optKey.ex.html";
    my $exPath = "$inputDir/$exFile";

    if( 0 ){
        #### This method uses an iframe to include dynamicaly the Example section
        # Setting height is a big problem without javascript.
        # With javascript the problem is that browsers consider two local files as two files
        # with two origins and we get cross-origin errors.
        my $exHtmlPath = -e $exPath ? $exFile
                                    : "../static/404_no_example.html";
        print($fh join( ' ',
                    '<iframe name="example"',
                      qq{src="$exHtmlPath"},
                      qq{title="Example for $optKey"},
                      'style="border:none;height:100vh;width:100%"',
                    "></iframe>\n"
                  )
             );
    }else{
        #### This method includes the Example section 'now' in the final html
        # Each time an uds file is updated we have to update 2 html files : <option>.ex.html and <option>.html
        # With this method the .ex.html is a tmp file and is not committed to git.
        $exPath = "$inputDir/../static/404_no_example.html" unless -e $exPath;
        open(my $ex_fh, '<', $exPath)
          || Fatal "Cannot open $exPath\n$!\n";
        my $body = 0;
        while( my $line = <$ex_fh> ){
            if( $line =~ m(<\s*body[^>]*>)i ){
                $body=1;
                next;
            }
            last if $line =~ m(<\s*/\s*body\s*>)i;
            print $fh $line if $body;
        }
        close($ex_fh);
    }

    ### Notes
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
print($fh indexHeader('name'));
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
print($fh indexHeader('category'));
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
print($fh indexHeader('type'));
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
print($fh indexHeader('keyword'));
for my $kw (sort keys %keywords){
    print $fh qq{  <dt>$kw</dt>\n};
    for my $optKey (@allOptionsSorted){
        next unless $optKey =~ /(\b|_)$kw(_|\b)/;
        print($fh qq{      <dd><a href="$optKey.html" target="option">$optKey</a></dd>\n});
    }
}
print($fh indexFooter('keyword'));

__END__
