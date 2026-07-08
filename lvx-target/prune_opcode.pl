#!/usr/bin/perl -w

my @kept_formats;

local $/ = ""; # paragraph mode
while (<>) {
  next if /^riscv/;
  my @par_lines = split /^/m;
  my @good_lines = grep {!(/^  X/ || /^  A[LSC]/ || /^ \*/ || /^..._X/)} @par_lines;
  my @kept_lines = grep {!(/^  [A-Z_0-9]+([BHWD][PQOX] )/ || / TLB/) || /CBX / || /CATDQ / } @good_lines;
  my @format_lines = ();
  my @encode_lines = ();
  foreach my $line (@kept_lines) {
    my $is_format = ($line =~ /\+\-\-\-/);
    push @format_lines, $is_format;
    my $is_encode = ($line =~ /3   2   1   0/);
    push @encode_lines, $is_encode;
  }
  push @format_lines, 0;
  for(my $i = 0; $i < scalar @kept_lines; $i++) {
    next if ($format_lines[$i] && $format_lines[$i+1]);
    next if ($encode_lines[$i] && !$format_lines[$i+1]);
    push @kept_formats, $kept_lines[$i] if $format_lines[$i];
    print $kept_lines[$i];
  }
}

my $filename = "lvx_formats.txt";
open(my $fh, ">", $filename)
    or die "Can't open > $filename: $!";

foreach my $kept_format (@kept_formats) {
  my ($format_name) = split / /, $kept_format;
  next unless $format_name;
  next if $format_name =~ /\.[MOWXY]/;
  print $fh "$format_name\n";
}

close $fh;

