#!/usr/bin/env perl

###############################################################################

use FindBin ();
use strict;
use Getopt::Std;
use File::Basename;
use FileHandle;
use vars qw($opt_f $opt_g $opt_r $opt_o $opt_p $opt_c $opt_m);

my $MOTHUR_BIN="/usr/bin/mothur";

my $PIPELINE_UTIL_PATH="$FindBin::Bin/pipeline_utilities";
print STDERR "Path of Pipeline Utilities: $PIPELINE_UTIL_PATH\n";

my $OTU_TO_ST_BIN="$PIPELINE_UTIL_PATH/OTU_To_SummaryTable/Convert_MothurSharedFile_to_SummaryTable.r";
my $TAXA_TO_ST_BIN="$PIPELINE_UTIL_PATH/Taxonomy_To_SummaryTable/Convert_MothurTaxonomy_to_SummaryTable.pl";
my $COUNT_NAMES_BIN="$PIPELINE_UTIL_PATH/Count_Names/Count_Names.pl";
my $ANNOTATE_OTU_WITH_GENUS_BIN="$PIPELINE_UTIL_PATH/Annotate_OTU_SummaryTable_Genera/Annotate_OTU_SummaryTable_Genera.pl";

my $POSTPIPELINE_TOOL_PATH="$FindBin::Bin/post_pipeline_tools";
my $OTU_TAXA_DEGREE_BIN="$POSTPIPELINE_TOOL_PATH/Analyze_Taxa_OTU_Degree/Analyze_Taxa_OTU_Degree.r";

my $TAXA_SUMTAB_FILTER_BIN="$FindBin::Bin/../Profile/SummaryTableUtilities/Filter_Categories_By_RemoveList.r";
my $TAXA_FILTER_LIST="$POSTPIPELINE_TOOL_PATH/Remove_Chloro_Mito/chloro_mito_genus.lst";

my $TAXA_SUMTAB_CLEANER_BIN="$FindBin::Bin/../Profile/SummaryTableUtilities/Clean_SummaryTable_Categories/Clean_SummaryTable_Categories.r";
my $SAMPLE_GREP_BIN="$FindBin::Bin/../Profile/SummaryTableUtilities/Filter_Samples_by_RegEx/Filter_Samples_by_RegEx.r";
my $READ_DEPTH_CUTOFF_BIN="$FindBin::Bin/../Profile/SummaryTableUtilities/Filter_Samples_By_Minimum_Sample_Count/Filter_Samples_By_Minimum_Sample_Count.r";

my $SUMMARIZE_SUMTAB_BIN="$FindBin::Bin/../Profile/SummaryTableUtilities/Summarize_SummaryTable.r";

my $DESC_DISTANCE_ANALYSIS_BIN="$FindBin::Bin/../Profile/distance_based/Cluster_Influencers/Cluster_Influencers.r";
my $DESC_DISTRIBUTION_ANALYSIS_BIN="$FindBin::Bin/../Profile/distribution_based/Plot_StackedBar/Plot_StackedBar.r";
my $DESC_ABUNDANCE_ANALYSIS_BIN="$FindBin::Bin/../Profile/abundance_based/Export_ALR_Values/Export_ALR_Values.r";

#my $CURRENT_16S_ALIGNMENT=
#	"/usr/local/devel/DAS/users/kli/SVN/DAS/16sDataAnalysis/trunk/16S_OTU_Generation/silva.nr_v119.align";

# Execution settings
my $TIMING_LOGNAME="timing_log.tsv";
my $MOTHUR_LOG="mothur.current.logfile";
my $COUNTS_LOGNAME="counts.logfile";
my $DEF_NUM_MISM=2;
my $DEF_NPROC=4;
my $DEF_CLUST_CUTOFF=0.45;
#my $DEF_CLUST_CUTOFF=0.3; if you just want .03

###############################################################################

getopts("f:g:r:o:m:p:c:");
my $usage = "usage: 

$0 
	-f <16S fasta file, quality trimmed>
	-g <groups file, read-to-sample id file>
	-r <reference 16S alignments, e.g. [abs path]/silva.nr_v119.align >
	-o <output directory>

	[-m <max mismatch for uniqueness in preclustering, default=$DEF_NUM_MISM>]
	[-p <num processors, default=$DEF_NPROC>]
	[-c <maximum distance saved in distance matrix, default=$DEF_CLUST_CUTOFF>]
		(note: to acquire clusters of .03, you may need .3
		       to acquire clusters of .10, you may need .45)

	This script will run through all the necessary steps to go from
	cleaned up FASTA sequences per sample, to OTU generation and taxonomic
	assignment.
	
	The (-f) 16S fasta file should quality, primer, adapter trimmed and length
	filtered.  This pipeline will not do any of that for you.  The fasta
	file should contain all the 16S sequence you want to cluster across
	all samples.

	The (-g) groups file contains a mapping from reads to sample id.
	You can generate this file with the script Assign_Sample_IDSs_To_Reads.pl.

	Make sure you specify the latest version of the 16S alignments for (-r).

	The (-o) output directory should be performed in scratch.  Then you
	can zip and archive the intermediate files.  You just want to make sure
	don't run this pipeline in a project directory where you may be charged
	for one time temporary disk usage.

	The number of processors can be as many as you have access to. It 
	will significantly improve the alignment to the reference step.


	You perform a test run based in the sample files in 'testing_files'.

	If perform a 'ls -ltr' in the output directory you will see the steps
	that have completed.  You will see a ##_<command> file for each 
	step in the pipeline.  These files are log files.  If you delete
	one of these log files, you can rerun the pipeline starting from that
	point automatically.

	You will also see:
		counts.logfile:	This contains a count of the reads and representatives
			that have been collapsed or removed during the pipeline
		timing_log.tsv: This contains a breakdown of the steps and how
			many CPU seconds and when the step was started.
		Summary_Tables: This contains the OTU and taxonomic summary tables
			across all samples.

";

if(!(
	defined($opt_f) && 
	defined($opt_g) && 
	defined($opt_r) && 
	defined($opt_o))){
	die $usage;
}

my @overall_begin_time=times;

my $input_fasta=$opt_f;
my $groups_file=$opt_g;
my $ref_16s_align=$opt_r;
my $output_dir=$opt_o;
my $num_proc=defined($opt_p)?$opt_p:$DEF_NPROC;
my $clust_cutoff=defined($opt_c)?$opt_c:$DEF_CLUST_CUTOFF;
my $preclust_diff=defined($opt_m)?$opt_m:$DEF_NUM_MISM;

print STDERR "Using Mothur at: $MOTHUR_BIN\n";
print STDERR "Input FASTA File: $input_fasta\n";
print STDERR "Groups File: $groups_file\n";
print STDERR "Reference 16S Alignments: $ref_16s_align\n";
print STDERR "Output Directory: $output_dir\n";
print STDERR "Num Processors: $num_proc\n";
print STDERR "Cluster Cutoff: $clust_cutoff\n";
print STDERR "Num Mismatch for Precluster: $preclust_diff\n";

if(!(-e $output_dir)){
	print STDERR "Making $output_dir...\n";
	mkdir $output_dir;
}else{
	print STDERR "$output_dir already exists...\n";
}
print "\n";

###############################################################################

sub get_elapsed_time{
	my $begin_ref=shift;
	my $end_ref=shift;

	my $begin_tot=0;
	my $end_tot=0;

	for(my $i=0; $i<4; $i++){
		$begin_tot+=${$begin_ref}[$i];
		$end_tot+=${$end_ref}[$i];
	}
	
	my $elapsed=$end_tot-$begin_tot;
	return($elapsed);
}

sub format_datetime{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);

	my $year_str=$year+1900;
	my $mon_str=$mon+1;
	my $day_str=$mday;
	my $date="$mon_str/$day_str/$year_str";
	
	my $time=sprintf("%02i:%02i:%02i", $hour,$min,$sec);
	return($date, $time);
}


my $timing_log="$output_dir/$TIMING_LOGNAME";

sub log_time{
	my $sdate=shift;
	my $stime=shift;
	my $edate=shift;
	my $etime=shift;
	my $begin_time_ref=shift;
	my $end_time_ref=shift;
	my $step=shift;
	my $notes=shift;

	my $run_time=get_elapsed_time($begin_time_ref, $end_time_ref);	

	my $print_hdr=0;
	if(!-e $timing_log){
		$print_hdr=1;
	}

	open(LOG, ">>$timing_log") || die "Could not open $timing_log for appending.\n";
	if($print_hdr){
		print LOG "Start_Date\tStart_Time\tEnd_Date\tEnd_Time\tCommand\tCPU_Time\tNotes\n";
	}
	my $run_time_str=sprintf("%3.2f", $run_time);
	print LOG "$sdate\t$stime\t$edate\t$etime\t$step\t$run_time_str\t$notes";
	print LOG "\n";
	close(LOG);

	return;
}

###############################################################################

sub check_logfile_for_errors{
	my $log_fname=shift;
	my $errors_found=0;
	open(FH, "<$log_fname") || die "Could not open $log_fname to check for errors.\n";

	while(<FH>){
		my $line=$_;
		if($line=~/\[ERROR\]/){
			$errors_found=1;
			last;
		}
	}

	close(FH);
	return($errors_found);
}


my $no_more_aborts=0;
my $step=1;

sub execute_mothur_cmd{
	my $cmd=shift;
	my $param=shift;

	$param=~s/\s+//g;	

	print STDERR "\n";
	print STDERR "***************************************************************\n";
	print STDERR "*  Executing $cmd in Mothur...\n";
	print STDERR "***************************************************************\n";

	my $step_str=sprintf("%02i", $step);
	my $logfile="$output_dir/$step_str\_$cmd";
	my $run_time=0;
	my $step_skipped=0;

	# Get start time
	my ($sdate_wall, $stime_wall)=format_datetime();
	my $notes="";

	my (@begin_time, @end_time);
	if(!(-e $logfile) || $no_more_aborts){
	
		my $exec_string="$MOTHUR_BIN \"#set.logfile(name=$output_dir/$MOTHUR_LOG,append=T);$cmd($param)\"";
		print STDERR "$exec_string\n";

		@begin_time=times;
		my $out=`$exec_string > $logfile\.tmp 2>&1`;
		@end_time=times;

		`mv $logfile\.tmp $logfile`;

		#open(FH, ">$logfile") || die "Could not open $logfile.\n";
		#print FH "$out\n";
		#close(FH);

		# Check for errors in the log file
		my $has_errors=check_logfile_for_errors($logfile);
		if($has_errors){
			print STDERR "\n\n";
			print STDERR "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n";
			print STDERR "!                                                              !\n";
			print STDERR "!  TERMINATING:  Error found in mothur log file!!!             !\n";
			print STDERR "!                Could not complete: $cmd\n";
			print STDERR "!                                                              !\n";
			print STDERR "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n\n";
			`mv $logfile $logfile.ERROR`;
			print STDERR "Check $logfile.ERROR for errors...\n\n";
			exit(-1);
		}	

		$no_more_aborts=1;
	}else{
		print STDERR "WARNING: $logfile already exists.\n";
		print STDERR "To rerun in this directory ($output_dir), you need to delete\n";
		print STDERR "the checkpoint/logfile's for the steps you want to repeat.\n";
		$notes="Skipped";
	}

	my ($edate_wall, $etime_wall)=format_datetime();

	log_time($sdate_wall, $stime_wall, $edate_wall, $etime_wall, 
		\@begin_time, \@end_time, "$step_str\_$cmd", $notes);

	$step++;
	return;
}

my $exec_cmd_ix=0;

sub exec_cmd{
	my $exec_string=shift;
	my $dir_name=shift;
	my $log_fname=shift;

	$exec_string=~s/\n//g;
	$exec_string=~s/\t/  /g;
	$exec_string=~s/^\s+//g;

	my ($command_path)=split /\s/, $exec_string;
	my ($command_only, $path)=fileparse($command_path);

	print STDERR "\n";
	print STDERR "***************************************************************\n";
	print STDERR "*  Executing $log_fname ($command_only) ...\n";
	print STDERR "***************************************************************\n";
	print STDERR "$exec_string\n";
	print STDERR "\n";

	my $res=`$exec_string 2>&1`;
	my $err=$!; # $! must be read immediate after ``'s

	$exec_cmd_ix++;
	my $exec_ix_str=sprintf("%02i", $exec_cmd_ix);

	my $log_fullfilename="$dir_name/$exec_ix_str\_$log_fname.log";

	open(LOG, ">$log_fullfilename") || die "Could not open $log_fullfilename for writing.\n";
	print LOG "$exec_string\n\n";
	print LOG "$res";
	close(LOG);

	if($err ne ""){
		print STDERR "!! ERROR Detected: !!\n$err\n";
		print STDERR "Check log file: $log_fullfilename\n\n";
		exit(-1);
	}

	return;
}

sub log_counts{
	my $fname=shift;
	my $comment=shift;
	my $exec_str="$COUNT_NAMES_BIN -n $fname -c $comment -o $output_dir/$COUNTS_LOGNAME";
	`$exec_str`;
}

###############################################################################

# Link fasta file to working directory
my ($name, $path)=fileparse($input_fasta);
print STDERR "Linking $input_fasta -> $output_dir/$name\n";
symlink $input_fasta, "$output_dir/$name";
my $in="$output_dir/$name";
$in=~s/\.fasta$//;

# Link groups file to working directory
my ($group_name, $group_path)=fileparse($groups_file);
print STDERR "Linking $groups_file -> $output_dir/$group_name\n";
symlink $groups_file, "$output_dir/$group_name";
my $group="$output_dir/$group_name";
$group=~s/\.groups//;

# Link 16S alignments and taxa file to working directory
my ($ref16s_name, $ref16s_path)=fileparse($ref_16s_align);
my $reference_name="16S_Reference";
print STDERR "Linking $ref_16s_align -> $output_dir/$reference_name.align\n";
symlink $ref_16s_align, "$output_dir/$reference_name.align";
# Find taxa map file
my $taxa_map=$ref_16s_align;
$taxa_map=~s/\.align$/.tax/;
# Use link as "name"
print STDERR "Linking $taxa_map -> $output_dir/$reference_name.taxa\n";
symlink $taxa_map, "$output_dir/$reference_name.tax";
my $reference_link="$output_dir/$reference_name.align";
my $tax_map="$output_dir/$reference_name.tax";


###############################################################################

execute_mothur_cmd(
	"unique.seqs",
	"fasta=$in.fasta"
);
log_counts("$in.names", "After_1st_Unique");
# Takes
# 	IN.fasta
# Makes 
# 	IN.unique.fasta
#	IN.names

execute_mothur_cmd(
	"align.seqs",
	"candidate=$in.unique.fasta, 
	template=$reference_link, 
	flip=t, 
	processors=$num_proc"
);
# Takes 
# 	IN.unique.fasta
# Makes
# 	IN.unique.align
#	IN.unique.align.report
#	IN.unique.flip.accnos

execute_mothur_cmd(
	"screen.seqs",
	"fasta=$in.unique.align, 
	optimize=start-end, 
	criteria=95,
	name=$in.names,
	group=$group.groups,
	processors=$num_proc"
);
# Takes
# 	GROUP.groups
# Makes
#	IN.unique.good.align
#	IN.unique.bad.accnos
#	IN.good.names
#	GROUP.good.groups
log_counts("$in.good.names", "After_Screening");

execute_mothur_cmd(
	"filter.seqs",
	"fasta=$in.unique.good.align,
	processors=$num_proc"
);
# Makes
#	IN.filter
#	IN.unique.good.filter.fasta


execute_mothur_cmd(
	"unique.seqs",
	"fasta=$in.unique.good.filter.fasta,
	name=$in.good.names"
);
# Makes
#	IN.unique.good.filter.unique.fasta
#	IN.unique.good.filter.names
log_counts("$in.unique.good.filter.names", "After_2nd_Unique");


execute_mothur_cmd(
	"pre.cluster",
	"fasta=$in.unique.good.filter.unique.fasta,
	name=$in.unique.good.filter.names,
	diffs=$preclust_diff,
	processors=$num_proc"
);
# Makes
#	IN.unique.good.filter.unique.precluster.map
#	IN.unique.good.filter.unique.precluster.fasta
#	IN.unique.good.filter.unique.precluster.names
log_counts("$in.unique.good.filter.unique.precluster.names", "After_Precluster");


execute_mothur_cmd(
	"chimera.uchime",
	"fasta=$in.unique.good.filter.unique.precluster.fasta, 
	name=$in.unique.good.filter.unique.precluster.names, 
	reference=self,
	processors=$num_proc"
);
# Makes
#	IN.unique.good.filter.unique.precluster.denovo.uchime.accnos
#	IN.unique.good.filter.unique.precluster.denovo.uchime.chimeras


execute_mothur_cmd(
	"remove.seqs",
	"accnos=$in.unique.good.filter.unique.precluster.denovo.uchime.accnos, 
	fasta=$in.unique.good.filter.unique.precluster.fasta, 
	name=$in.unique.good.filter.unique.precluster.names,
	group=$group.good.groups"
);
# Makes
# 	IN.unique.good.filter.unique.precluster.pick.names
# 	IN.unique.good.filter.unique.precluster.pick.fasta
#	IN.good.pick.groups
log_counts("$in.unique.good.filter.unique.precluster.pick.names", "After_Chimera_Check");



execute_mothur_cmd(
	"classify.seqs",
	"fasta=$in.unique.good.filter.unique.precluster.pick.fasta, 
	name=$in.unique.good.filter.unique.precluster.pick.names, 
	template=$ref_16s_align,
	taxonomy=$tax_map,
	cutoff=80,
	group=$group.good.pick.groups,
	processors=$num_proc"
);
# Makes
#	IN.unique.good.filter.unique.precluster.pick.REFERENCE.wang.flip.accnos
#	IN.unique.good.filter.unique.precluster.pick.REFERENCE.wang.tax.summary
#	IN.unique.good.filter.unique.precluster.pick.REFERENCE.wang.taxonomy

execute_mothur_cmd(
	"dist.seqs",
	"fasta=$in.unique.good.filter.unique.precluster.pick.fasta, 
	cutoff=$clust_cutoff,
	processors=$num_proc"
);
# Makes
#	IN.unique.good.filter.unique.precluster.pick.dist

execute_mothur_cmd(
	"cluster",
	"column=$in.unique.good.filter.unique.precluster.pick.dist, 
	name=$in.unique.good.filter.unique.precluster.pick.names,
	precision=100
	"
);
# Makes
#	IN.unique.good.filter.unique.precluster.pick.opti_mcc.steps
#	IN.unique.good.filter.unique.precluster.pick.opti_mcc.list
#	IN.unique.good.filter.unique.precluster.pick.opti_mcc.sensspec
#	IN.unique.good.filter.unique.precluster.pick.opti_mcc.sabund
#	IN.unique.good.filter.unique.precluster.pick.opti_mcc.rabund


execute_mothur_cmd(
	"make.shared",
	"list=$in.unique.good.filter.unique.precluster.pick.opti_mcc.list, 
	group=$group.good.pick.groups, 
	label=0.03"
);
# Makes
#	IN.unique.good.filter.unique.precluster.pick.opti_mcc.<per groups>.rabund
#	IN.unique.good.filter.unique.precluster.pick.opti_mcc.shared

execute_mothur_cmd(
	"classify.otu",
	"taxonomy=$in.unique.good.filter.unique.precluster.pick.$reference_name.wang.taxonomy,
	list=$in.unique.good.filter.unique.precluster.pick.opti_mcc.list,
	name=$in.unique.good.filter.unique.precluster.pick.names,
	group=$group.good.pick.groups,
	label=0.03"
);
# Makes
# 	IN.unique.good.filter.unique.precluster.pick.an.0.03.cons.taxonomy
#	IN.unique.good.filter.unique.precluster.pick.an.0.03.cons.tax.summary


###############################################################################

# Convert OTU info into Summary Table  
# 	IN.unique.good.filter.unique.precluster.pick.an.shared into Summary Table

my ($sdate_wall, $stime_wall)=format_datetime();
my @sumtab_start_time=time;

my $out_root=$name;
$out_root=~s/\.fasta$//;

my $st_dir="$output_dir/Summary_Tables";
mkdir $st_dir;

my $exec_string="
	$OTU_TO_ST_BIN
		-i $in.unique.good.filter.unique.precluster.pick.opti_mcc.shared
		-o $st_dir/$out_root.otu
";
exec_cmd($exec_string, "$st_dir", "shared_to_summary_table");

# Annotate OTUs with Genus
$exec_string="
	$ANNOTATE_OTU_WITH_GENUS_BIN
		-s $st_dir/$out_root.otu.97.summary_table.tsv
		-m $in.unique.good.filter.unique.precluster.pick.opti_mcc.0.03.cons.taxonomy
		-o $st_dir/$out_root.otu.97.genus.summary_table.tsv
";
exec_cmd($exec_string, "$st_dir", "annotate_otu_with_genera");	

# Convert Taxonomy files into Summary Table
#	Will need IN.unique.good.filter.unique.precluster.pick.REFERENCE.wang.taxonomy
#		  IN.unique.good.filter.unique.precluster.pick.names
#		  IN.good.pick.groups

my $exec_string="
	$TAXA_TO_ST_BIN
		-t $in.unique.good.filter.unique.precluster.pick.$reference_name.wang.taxonomy
		-n $in.unique.good.filter.unique.precluster.pick.names
		-g $group.good.pick.groups
		-o $st_dir/$out_root.taxa
";
exec_cmd($exec_string, "$st_dir", "taxonomy_to_summary_table");

my @sumtab_end_time=time;

my ($edate_wall, $etime_wall)=format_datetime();

log_time($sdate_wall, $stime_wall, $edate_wall, $etime_wall, 
	\@sumtab_start_time, \@sumtab_end_time, "generate.summary_tables", "");

###############################################################################
###############################################################################

# Compute OTU to taxa degrees
# 	Will need IN.unique.good.filter.unique.precluster.pick.opti_mcc.0.03.cons.taxonomy

my $exec_string="
	$OTU_TAXA_DEGREE_BIN
		-i $in.unique.good.filter.unique.precluster.pick.opti_mcc.0.03.cons.taxonomy
		-o $st_dir/0.03.cons.taxonomy
";
exec_cmd($exec_string, "$st_dir", "otu_taxa_degree");

###############################################################################

# Filter out mito, chlr and unknown
my $exec_string="
	$TAXA_SUMTAB_FILTER_BIN
		-i $st_dir/$out_root.taxa.genus.summary_table.tsv
		-l $TAXA_FILTER_LIST \
		-o $st_dir/$out_root.taxa.genus.cmF.summary_table.tsv
";
exec_cmd($exec_string, "$st_dir", "remove_chl_mit_from_sumtab");


# Clean the summary table taxa names
my $exec_string="
	$TAXA_SUMTAB_CLEANER_BIN
		-i $st_dir/$out_root.taxa.genus.cmF.summary_table.tsv
		-o $st_dir/$out_root.taxa.genus.cmF.cln.summary_table.tsv
";
exec_cmd($exec_string, "$st_dir", "clean_sumtab_taxa_names");


# Split experimental samples
my $exec_string="
	$SAMPLE_GREP_BIN
		-i $st_dir/$out_root.taxa.genus.cmF.cln.summary_table.tsv
		-r \"^00[0-9][0-9]\\.\"
		-o $st_dir/$out_root.taxa.genus.cmF.cln.exp
";
exec_cmd($exec_string, "$st_dir", "extract_experimental_samples");

# Split control samples
my $exec_string="
	$SAMPLE_GREP_BIN
		-i $st_dir/$out_root.taxa.genus.cmF.cln.summary_table.tsv
		-k \"^00[0-9][0-9]\\.\"
		-o $st_dir/$out_root.taxa.genus.cmF.cln.ctl
";
exec_cmd($exec_string, "$st_dir", "extract_control_samples");

# Remove low count samples
my $exec_string="
	$READ_DEPTH_CUTOFF_BIN
		-i $st_dir/$out_root.taxa.genus.cmF.cln.exp.summary_table.tsv
		-c 750,1000,2000,3000
		-o $st_dir/$out_root.taxa.genus.cmF.cln.exp
";
exec_cmd($exec_string, "$st_dir", "filter_samples_by_read_depth");


###############################################################################

# Summarize all before filtering
my $exec_string="
	$SUMMARIZE_SUMTAB_BIN
		-i $st_dir/$out_root.taxa.genus.summary_table.tsv
		> $st_dir/$out_root.taxa.genus.summary.txt
";
exec_cmd($exec_string, "$st_dir", "summarize_all_before_filtering");
#
# Summarize Experimental after filtering (750)
my $exec_string="
	$SUMMARIZE_SUMTAB_BIN
		-i $st_dir/$out_root.taxa.genus.cmF.cln.exp.min_0750.summary_table.tsv
		> $st_dir/$out_root.taxa.genus.cmF.cln.exp.min_0750.summary.txt
";
exec_cmd($exec_string, "$st_dir", "summarize_experimental_after_filtering");
#
# Summarize Control before filtering
my $exec_string="
	$SUMMARIZE_SUMTAB_BIN
		-i $st_dir/$out_root.taxa.genus.cmF.cln.ctl.summary_table.tsv
		> $st_dir/$out_root.taxa.genus.cmF.cln.ctl.summary.txt
";
exec_cmd($exec_string, "$st_dir", "summarize_control_before_filtering");

###############################################################################

# Descriptive statistics
my $desc_stat_dir="$st_dir/Descriptive";
mkdir $desc_stat_dir;

my $exec_string="
	$DESC_DISTANCE_ANALYSIS_BIN
		-i $st_dir/$out_root.taxa.genus.cmF.cln.summary_table.tsv
		-o $desc_stat_dir/$out_root
		-d man
		-p 15
		-k 6
		-s \";\"
";
exec_cmd($exec_string, "$desc_stat_dir", "distance_desc_analysis");

my $exec_string="
	$DESC_DISTRIBUTION_ANALYSIS_BIN
		-i $st_dir/$out_root.taxa.genus.cmF.cln.summary_table.tsv
		-o $desc_stat_dir/$out_root
		-s \";\"
";
exec_cmd($exec_string, "$desc_stat_dir", "distribution_desc_analysis");


my $exec_string="
	$DESC_ABUNDANCE_ANALYSIS_BIN
		-s $st_dir/$out_root.taxa.genus.cmF.cln.summary_table.tsv
		-o $desc_stat_dir/$out_root
		-x \";\"
";
exec_cmd($exec_string, "$desc_stat_dir", "abundance_desc_analysis");

##############################################################################

print STDERR "done.\n";
