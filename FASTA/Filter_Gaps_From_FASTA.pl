#!/usr/bin/env perl

###############################################################################

use strict;
use Getopt::Std;
use vars qw($opt_i $opt_o);

getopts("i:o:");
my $usage = "usage: 
$0 
	-i <input fasta file>
	-o <output fasta file>

	Reads in a fasta file and writes out a fasta file without the .'s and -'s in it.

	Useful for converting a gapped/alignment fasta to a regular fasta.

";

if(!defined($opt_i) || !defined($opt_o)){
	die $usage;
}

my $input_fasta=$opt_i;
my $output_fasta=$opt_o;

###############################################################################

print STDERR "Processing FASTA file...\n";

open(IN_FASTA, "<$input_fasta") || die "Could not open $input_fasta\n";
open(OUT_FASTA, ">$output_fasta") || die "Could not open $output_fasta\n";

my ($defline, $prev_defline, $sequence);
while(<IN_FASTA>){
	chomp;
	
	if(/^>/){
		$defline=$_;
		if($sequence ne ""){
			process_record($prev_defline, $sequence);
			$sequence="";
		}
		$prev_defline=$defline;
	}else{
		$sequence.=$_;
	}
}
process_record($prev_defline, $sequence);

print STDERR "Completed.\n";

###############################################################################

sub process_record{
	my $defline = shift;
	my $sequence = shift;

	print OUT_FASTA "$defline\n";

	$sequence=~s/-//g;
	$sequence=~s/\.//g;

	my $length=length($sequence);
	my $width=80;
	my $pos=0;
	do{
		my $out_width=($width>$length)?$length:$width;
		print OUT_FASTA substr($sequence, $pos, $width) . "\n";
		$pos+=$width;
		$length-=$width;
	}while($length>0);
}

###############################################################################