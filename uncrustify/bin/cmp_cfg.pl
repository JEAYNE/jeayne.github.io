#!/usr/bin/perl

use v5.36;
use strict;

use Getopt::Long;
use FindBin qw($Bin $Script);
use lib "$Bin/.";

### Global variables used by this script and the module UDocTools
our $verbose = 0;  # set by user on command line
our $ucBin;        # set by user on command line (default is $Bin)

use UDocTools qw(dumpit slurpFile loadOptionDescriptions SayError Fatal);

### Global variables used by this script
$|=1;
my $binDir     =  $Bin;                  # where to find the uncrustify binary
my $outputFile = "-";
my $byName     = 0;
my $byCategory = 0;

# Script name  (without the .pl) used in the error messages
$Script =~ s/^(.+)\.pl$/$1/i;

GetOptions (
  "bindir=s"     => \$binDir,     # string
  "outputfile=s" => \$outputFile, # string
  "byname"       => \$byName,     # flag
  "bycategory"   => \$byCategory, # flag
  "verbose"      => \$verbose     # flag
) or Fatal("Invalid command line argument.");

$binDir .= '/'  if $binDir && $binDir !~ m(/$);
$ucBin   = "${binDir}uncrustify.exe";

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

exit(3) if $err;

# a ref to a hash of hash   Used to collect info and then sort options by name
my $options = loadOptionDescriptions();

# dumpit('Options' => $options); exit;

my %cfg;  # hash of hash
for my $file (@ARGV){
    open(my $fh, '<', $file)
      || Fatal "Cannot open $file\n$!";
    $cfg{$file} = {};
    my $cfgFile = $cfg{$file};
    while( my $line = <$fh> ){
        next unless $line =~ /^\s*(\w+)\s*=\s*([-\w]+)/ ;
        $cfgFile->{$1} = $2;
    }
    close($fh);
    # dumpit("Configuration from $file", $cfg{$file});
}

# dumpit("Configurations to compare", \%cfg);

#  options     | default | fileA | fileB | ...
# -------------+---------+-------+-------+- - -
# name_of_key1 | val     | val   | val   | ...
# name_of_key1 | val     | val   | val   | ...
# ...

### build header
my $header = "<th>Options</th>\n"
           . "<th>default</th>\n";
for my $file (@ARGV){
    (my $name = $file) =~ s!^.*?([^/\\]+)$!$1!;
    $header .= "<th>$name</th>\n";
}

### build body

my $bodyName = '';
if( $byName ){
    # Body sorted alphabetically
    for my $optKey (sort keys %{$options}){
        next if $optKey eq 'header';
        my $default = $options->{$optKey}{ValueDefault};
        my $tr = "<td>$optKey</td>\n"
               . "<td>$default</td>\n";
        for my $file (@ARGV){
            my $optVal = $cfg{$file}{$optKey} || '';
            if( ($optVal eq '') || ($optVal eq $default) ){
                $tr .= "<td></td>\n";
            }else{
                $tr .= "<td>$optVal</td>\n";
            }
        }
        $bodyName .= "<tr>\n$tr</tr>\n"
    }
}

my $bodyCategory = '';
if( $byCategory ){
    ## Body by category and sorted alphabetically

    # Extract name of catrgeory from 'header'
    my @Categories = split('\|', $options->{header}{categories}||'');

    # Parse all options to make groups by category
    my %categories;
    for my $optKey (sort keys %{$options}){
        next if $optKey eq 'header';
        my $catName = $Categories[$options->{$optKey}{Category}]||'unknow';
        $categories{$catName} ||= [];
        push(@{$categories{$catName}}, $optKey);
    }
    my $nCol = @ARGV + 2;

    for my $catName (sort keys %categories){
        $bodyCategory .= qq(<td colspan="$nCol" style="background-color: DimGray;"><h3>$catName</h3></td>\n);
        for my $optKey (@{$categories{$catName}}){
            next if $optKey eq 'header';
            my $default = $options->{$optKey}{ValueDefault};
            my $tr = "<td>$optKey</td>\n"
                   . "<td>$default</td>\n";
            for my $file (@ARGV){
                my $optVal = $cfg{$file}{$optKey} || '';
                if( ($optVal eq '') || ($optVal eq $default) ){
                    $tr .= "<td></td>\n";
                }else{
                    $tr .= "<td>$optVal</td>\n";
                }
            }
            $bodyCategory .= "<tr>\n$tr</tr>\n"
        }
    }
}

my $fh;
if( $outputFile && ($outputFile ne '-') ){
    open( $fh, '>', $outputFile)
      || Fatal "Cannot create $outputFile\n$!";
}else{
    $fh = \*STDOUT;
}

print $fh qq{
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Comparison of Uncrustify configurations</title>
  <style>
    :root { color-scheme: light dark; }
  </style>
</head>
<body style=":root {color-scheme: light dark;}">
};

print $fh qq{
<h1>Comparison sorted by name</h1>
<table border="1"><tr>
$header</tr>
$bodyName
</table>
} if $byName;

print $fh "<p><hr></p>\n" if $byName && $byCategory;

print $fh qq{
<h1>Comparison sorted by category</h1>
<table border="1"><tr>
$header</tr>
$bodyCategory
</table>
} if $byCategory;

print $fh qq{
<h1>To see the comparison you must use <pre>--byName</pre> and/or <pre>--byCategory</pre></h1>
} unless $byName || $byCategory;

print $fh qq{
</body>
</html>
};

close ($fh);

__END__
