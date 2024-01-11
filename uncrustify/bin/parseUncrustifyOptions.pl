#!/usr/bin/perl

use warnings;
use strict;

use Getopt::Long; # https://perldoc.perl.org/Getopt::Long
use Data::Dumper; # https://metacpan.org/pod/Data::Dumper

# global variables used by subroutines
(my $myName = $0) =~ s!^.*?([^/\\]+)$!$1!;
my $ucBin   = '';
my $verbose = 0;

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
  return $result;
}

##
## main
##

$|=1;
my $binDir  = '';
my %options;
my $outputDir;

GetOptions (
  "bindir=s"     => \$binDir,    # string
  "outputdir=s"  => \$outputDir, # string
  "verbose"      => \$verbose    # flag
) or Fatal("Invalid command line arguments");

$binDir .= '/'  if $binDir && $binDir !~ m(/$);
$ucBin   = "${binDir}uncrustify.exe";

my $err=0;
if( $binDir  && ! -d $binDir ){
    Error("Path '$binDir' doesn't exist.");
    $err++;
}elsif( ! -e $ucBin ){
    Error("File '$ucBin' doesn't exist.");
    $err++;
}
if( $outputDir && ! -d $outputDir ){
    Error("Path '$outputDir' doesn't exist");
    $err++;
}
exit(3) if $err;

my $ucVersion = getOption('--version');
print "Running $ucVersion\n";

open(PIPE, '-|', $ucBin, '--universalindent')
  || Fatal("Can't exec '$ucBin'\n$!");

my $optName;
my $optCount = 0;
while(my $line = <PIPE>){
    chomp $line;
    # print "$line\n";
    next if $line =~ /^\s*(#.*)?$/;
    if( $line =~ /^\s*\[([^\]]+)\]/ ){
        # got "[option name]"
        $optName = $1;
        $options{$optName}={};
        $optCount++;
        printf("%4d: %s\n", $optCount, $optName);
    }elsif( $line =~ /^\s*(\w*)\s*=\s*(.*)$/ ){
        # got "name=value"
        $options{$optName}{$1}=$2;
        # printf("      %s=%s\n", $1, $options{$optName}{$1});
    }else{
        print "Ignoring: '$line'\n";
    }
}

close(PIPE);

my $fname = "$outputDir/Summary.txt";
open(my $fh, '>', $fname)
  || Fatal("Can't create summary $fname:\n$!");

$Data::Dumper::Indent   = 1;
$Data::Dumper::Sortkeys = 1;
print $fh Dumper(\%options);

close($fh);
$optCount -= 1;  # the [header] section is not an option.
print "\n$optCount options + 'header' wrote in summary: $fname\n";

## Parse headers
my @Categories = split('\|', $options{header}{categories}||'');

## Save
for my $optKey (sort keys %options){
    next if $optKey eq 'header';

    (my $optName = lc($optKey) ) =~ s/ /_/g;
    my $fname="$outputDir/$optName.html";
    open(my $fh, '>', $fname)
      || Fatal("Can't save option in $fname:\n$!");

    ### html header
    print($fh join("\n",
                '<!doctype html>',
                '<html>',
                '<head>',
                '  <meta charset="utf-8">',
                "  <title>$optName - uncrustify options</title>",
                '</head>',
                '<body style="color:white;background-color:black;">'
              ), "\n");

    ### name of the option as used in the config file
    printf($fh qq{<h1><pre style="color:yellow">%s</pre></h1>\n}, $optName);

    my $option = $options{$optKey};
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
        my $max = delete $option->{MaxVal};
        my $min = delete $option->{MinVal};
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
        Warning("Unexpected value '$type' for field 'EditorType' in option '$optName'");
    }
    printf($fh "  Category: %s\n", $Categories[$option->{Category}]||'unknow');
    printf($fh "      Type: $type $expected\n");
    printf($fh "   Default: $default\n");
    delete $option->{Category};

    # extract the description now (used later)
    my $desc = delete $option->{Description};

    # All options have Enabled=false, excepted 'indent_with_tabs'
    # What is the goal of this propreties ?
    delete $option->{Enabled};

    # print unmanaged properties (empty list expected)
    if( 0 < keys %{$option} ){
        print($fh "Other properties\n");
        for my $prop (sort keys %{$option}){
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
    $fname = "../examples/$optName.html";
    $fname = "../examples/404_no_example.html" unless -e $fname;
    print($fh join( ' ',
                    '<iframe',
                      qq{src="$fname"},
                      qq{title="Example for $optName"},
                      'name="example"',
                      'style="border:none;height:auto;width:100%"',
                    "></iframe>\n"
                  )
         );

    ### Notes
    print($fh "<h3>Notes</h3><ul>\n");
    print($fh qq{<li> Report problems related to this documentation <a href="https://github.com/JEAYNE/jeayne.github.io/issues" target="_blank">here</a>.\n});
    print($fh qq{<li> This documentation project is <b>not</b> managed by the <a href="https://github.com/uncrustify" target="_blank">uncrustify</a> team.\n});
    print($fh "</ul>\n");

    ### close the html page
    print($fh "</body>\n</html>\n");
    close($fh);
}
