#!/usr/bin/perl -w

use Data::Dumper;

my %kept_format;

my $filename = "lvx_formats.txt";
open(my $fh, "<", $filename)
    or die "Can't open < $filename: $!";

while (<$fh>) {
  next unless /^(\w[\w\.]*)/;
  my $formatID = $1;
  $kept_format{$formatID} = 1;
}

close $fh;

use YAML::XS;

# Load YAML input into %$Description.
local $/;
my $Description = Load(<>);

foreach my $format (@{$$Description{Format}}) {
  my $formatID = $$format{ID} || die "Missing ID for Format";
  next unless $kept_format{$formatID};
  my $what = $$format{what};
  next if $what =~ /ONLY.FOR.H/;
  my $encoding = $$format{encoding};
  my $operands = $$format{operands};
  my $syntax = $$format{syntax};
  my $scheduling = $$format{scheduling};
  print<<"EOT";
  - ID: $formatID
    what: $what
    encoding: $encoding
EOT
  my $sep = "    operands: [ ";
  foreach my $operand (@{$operands}) {
    #print "\n\t", Dumper($operands);
    print $sep;
    if (!ref $operand) {
      print $operand;
    } elsif (ref $operand eq 'HASH') {
      my ($method) = keys %{$operand};
      print "{ $method: ";
      my ($fields) = $$operand{$method};
      if (!ref $fields) {
        print $fields;
      } elsif (ref $fields eq 'ARRAY') {
        print "[ ", (join ", ", @{$fields}), " ]";
      } else {
        die "operand fields must be ARRAY";
      }
      print " }";
    } else {
      die "operand must be scalar or HASH";
    }
    $sep = ", ";
  }
  print " ]\n" if @{$operands};
  print<<"EOT";
    syntax: "$syntax"
    scheduling: $scheduling
EOT
}

    #encoding: simple
    #operands: [ ccbcomp, { singleReg: registerZ }, { singleReg: registerY }, pcrel11s2 ]
    #syntax: "%0%1 %2, %3 ? %4"
    #properties: { '%0': Control;Conditional, '%4': Target }
    #scheduling: BCU_BRRP2

