package UDocTools;

use v5.36;
use strict;

use parent 'Exporter';
our @EXPORT    = qw(SayDebug SayInfo SayWarning SayError Fatal);
our @EXPORT_OK = qw(dumpit getOption loadOptionDescriptions);

### Subroutines to display a message with various levels of severity

sub SayDebug {
  $::verbose>1 && print "\e[94m", shift, "\e[0m\n";
}

sub SayInfo {
  $::verbose!=0 && print "\e[92m", shift, "\e[0m\n";
}

sub SayWarning {
  print STDERR "$::Script\e[93m WARNING: ", shift, "\e[0m\n";
}

sub SayError {
  print STDERR "$::Script\e[91m ERROR: ", shift, "\e[0m\n";
}

sub Fatal {
  print STDERR "$::Script\e[91m ERROR: ", shift, "\e[0m\n";
  die "\n";
}


#
# Usages:
#  $a = dumpit(\%list);  # 1 parameter: Don't print, return the dump
#  dumpit('Products' => \%prod, 'Vendors' => $contacts );  # 2xN parameters: print
sub dumpit {

  use Data::Dumper;

  local $Data::Dumper::Useperl       = 1;
  local $Data::Dumper::Terse         = 1;
  local $Data::Dumper::Sortkeys      = 1;
  local $Data::Dumper::Indent        = 1;
  local $Data::Dumper::Useqq         = 1;
  local $Data::Dumper::Quotekeys     = 0;
  local $Data::Dumper::Deparse       = 1;
  local $Data::Dumper::Trailingcomma = 1;

  return Dumper($_[0]) if @_==1;

  if (@_ % 2) {
    say "ERROR dumpit() requires 1 or 2n parameters!\n";
    return;
  }

  while (my($name, $ref) = splice(@_, 0, 2)) {
    say $name, ': ', Dumper($ref);
  }

  return;
}

# Routine used to check the path,
# and get the version of uncrustify
sub getOption {
  my $option = shift || '';
  open(PIPE, '-|', $::ucBin, $option)
    || Fatal("Can't exec '$::ucBin'\n$!");
  my $result=<PIPE>;
  close(PIPE);
  chomp($result);
  return $result;
}

# Load the output of "uncrustify ----universalindent" in memory
# For each option we get a decription like this:
#
#   [Debug Sort The Tracks]
#   Category=13
#   Description="<html>sort (or not) the tracking info.<br/><br/>Default: true</html>"
#   Enabled=false
#   EditorType=boolean
#   TrueFalse=debug_sort_the_tracks\s*=\s*true|debug_sort_the_tracks\s*=\s*false
#   ValueDefault=true

sub loadOptionDescriptions {

    my $ucVersion = getOption('--version');
    $ucVersion = (split('-', $ucVersion))[1];
    print "Running Uncrustify version $ucVersion\n";

    open(PIPE, '-|', $::ucBin, '--universalindent')
      || Fatal("Can't exec '$::ucBin'\n$!");

    my %options;
    my $optKey;
    my $optCount = 0;
    while(my $line = <PIPE>){
        chomp $line;
        # print "$line\n";
        next if $line =~ /^\s*(#.*)?$/;
        if( $line =~ /^\s*\[([^\]]+)\]/ ){
            # got "[option name]"
            my $optName = $1;
            ($optKey = lc($optName)) =~ s/ /_/g;
            $options{$optKey}={
                optName => $optName,    # Align Func Params Gap
                optKey  => $optKey,     # align_func_params_gap
            };
            $optCount++;
            printf("%4d: %s\n", $optCount, $optName);
        }elsif( $line =~ /^\s*(\w*)\s*=\s*(.*)$/ ){
            # got "name=value"
            $options{$optKey}{$1}=$2;
        }else{
            print "Ignoring: '$line'\n";
        }
    }
    close(PIPE);
    return \%options;
}

1;
