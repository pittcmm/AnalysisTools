#!/usr/bin/env Rscript

###############################################################################

library('getopt');

params=c(
	"directory", "d", 1, "character"
);

opt=getopt(spec=matrix(params, ncol=4, byrow=TRUE), debug=FALSE);

script_name=unlist(strsplit(commandArgs(FALSE)[4],"=")[1])[2];

LOG_FILE_NAME="fastq_qc_log";
LOG_FILE_EXT="tsv";
CTL_REGEX="^00[0-9][0-9]\\.";

usage = paste (
	"\nUsage:\n\n", script_name,
	"\n",
	"	-d <FASTQ QC Pipeline Output Directory>\n",
	"\n",
	"This script should be run after the QC pipeline has\n",
	"completed.\n",
	"\n",
	"The files: ", LOG_FILE_NAME, ".*", LOG_FILE_EXT, "\n",
	"will be concatenated together.\n",
	"\n",
	"The 'merged' numbers for forward, reverse, and paired\n",
	"will be accumulated.\n",
	"\n",
	"paired will be categorized according to:\n",
	"	<750   Reads\n",
	"	<1000  Reads\n",
	"	<2000  Reads\n",
	"	<3000  Reads\n",
	"\n",
	"\n");

if(
	!length(opt$directory)
){
	cat(usage);
	q(status=-1);
}

###############################################################################

QC_LogDir=opt$directory;

cat("\n")
cat("QC Result Directory: ", QC_LogDir, "\n");

###############################################################################

# Find list of files in directory
pattern=paste(LOG_FILE_NAME, "\\.\\d+\\.", LOG_FILE_EXT, sep="");
cat("Log Pattern: ", pattern, "\n");
qc_log_files_arr=sort(list.files(QC_LogDir, pattern=pattern));
qc_log_fullpath_arr=paste(QC_LogDir, "/", qc_log_files_arr, sep="");
print(qc_log_fullpath_arr);

cat("\n");
cat("Found these log files:\n");
print(qc_log_files_arr);

num_log_files=length(qc_log_files_arr);

cat("\nNumber of log files: ", num_log_files, "\n", sep="");

# Parse files names
name_parse=strsplit(qc_log_files_arr, "\\.");
indices_found=numeric();
for(i in 1:num_log_files){
	indices_found[i]=as.numeric(name_parse[[i]][2]);
}
indices_found=sort(indices_found);

cat("Indices Found:\n");
print(indices_found);

# Confirm all files in range exist
if(all(indices_found==(1:num_log_files))){
	cat("Indices found across expected range. (1 - ", num_log_files, ")\n", sep="");
}else{
	cat("Error:  Unexpected differences between found and expected log file indices.\n");
}

###############################################################################

full_file_fname=paste(QC_LogDir, "/",LOG_FILE_NAME, "._ALL_.", LOG_FILE_EXT, sep="");
cat("Concatenating all files into: ", full_file_fname, "\n", sep="");

full_tab=data.frame();

for(i in 1:num_log_files){
	cur_file=qc_log_files_arr[i];
	cat("Loading: ", cur_file, "\n"); 
	tab=read.table(qc_log_fullpath_arr[i], header=T, sep="\t", comment.char="");
	
	cnam=colnames(tab);
	cnam[1:3]=c("SampleID", "Direction", "QCStep");
	colnames(tab)=cnam;

	full_tab=rbind(full_tab, tab);
}

uniq_samp_ids=sort(unique(as.character(full_tab[,"SampleID"])));
num_samp_ids=length(uniq_samp_ids);

cat("Number of Samples Read:\n", num_samp_ids, "\n");

write.table(full_tab, file=full_file_fname, sep="\t", quote=F, row.names=F);

###############################################################################

cat("Splitting out controls based on: ", CTL_REGEX, "\n");
ctl_ix=grep(CTL_REGEX, full_tab[,"SampleID"]);

ctl_tab=full_tab[ctl_ix,,drop=F];
exp_tab=full_tab[-ctl_ix,,drop=F];

ctl_ids=as.character(ctl_tab[,"SampleID"]);
exp_ids=as.character(exp_tab[,"SampleID"]);

uniq_ctl_ids=sort(unique(ctl_ids));
uniq_exp_ids=sort(unique(exp_ids));

cat("Control IDs:\n");
print(uniq_ctl_ids);
cat("\n");
cat("Experimental IDs:\n");
print(uniq_exp_ids);
cat("\n");

# Extract out first sample's steps as a basis
first_exp=uniq_exp_ids[1];
first_entry=exp_tab[first_exp==exp_ids,];

forw_steps=as.character(first_entry[first_entry[,"Direction"]=="F","QCStep"]);
reve_steps=as.character(first_entry[first_entry[,"Direction"]=="R","QCStep"]);

rev_reads_found=T;
if(length(reve_steps)==0){
	rev_reads_found=F;	
}

if(length(forw_steps)==length(reve_steps) && !all(forw_steps==reve_steps)){
	cat("Error: Forward and Reverse steps don't match.\n");
	cat("Forward:\n");
	print(forw_steps);
	cat("Reverse:\n");
	print(reve_steps);
	cat("\n");
	quit(-1);
}

qc_steps=forw_steps;

cat("Step Order Identified:\n");
print(qc_steps);

plot_step_histograms=function(table, target_ids, directions, steps, target_stats, title){

	num_steps=length(steps);

	maxs=apply(table[,target_stats,drop=F], 2, function(x){max(x, na.rm=T)} );
	cat("Maxes:\n");
	print(maxs);

	for(stat_ix in target_stats){

		if(length(intersect(stat_ix, c("NumRecords", "NumBases")))){
			disp_stat=paste("log10(", stat_ix, ")",sep="");
			log_trans=T;
		}else{
			disp_stat=paste(stat_ix, sep="");
			log_trans=F;
		}

		cat("Stat:", stat_ix, "\n", sep="");

		par(mfcol=c(num_steps,length(directions)));
		par(mar=c(3,4,4,1));
		par(oma=c(0,0,3,0));
	
		for(cur_dir in directions){
			for(step_ix in steps){
				cat("\tStep:", step_ix, "(", cur_dir, ")\n", sep="");

				srows=(table[,"QCStep"]==step_ix & table[,"Direction"]==cur_dir);
				values=table[srows, stat_ix];
				med_val=median(values, na.rm=T);

				if(log_trans){
					hist(log10(values+1), 
						breaks=seq(0, log10(maxs[stat_ix])*1.025, length.out=40), 
						xlab="", 
						main=paste(cur_dir, ": ", step_ix, "\nmedian = ", med_val, sep=""));
					abline(v=median(log10(values+1)), col="blue");
				}else{
					hist(values, 
						breaks=seq(0, maxs[stat_ix]*1.025, length.out=40), 
						xlab="",
						main=paste(step_ix, "\nmedian = ", med_val, sep=""));
					abline(v=median(values, na.rm=T), col="blue");
				}

			}
		}
		mtext(disp_stat, side=3, outer=T, cex=2, font=2);

	}	
}




pdf(paste(LOG_FILE_NAME, ".qc_log_summary.pdf", sep=""), height=11, width=8.5);

partial_tab=exp_tab[,
	c("SampleID", "Direction", "QCStep", "NumRecords", "NumBases", "LB95Len", "LB95QV")];

target_stats=c("NumRecords", "NumBases", "LB95Len", "LB95QV");
	
plot_step_histograms(partial_tab, exp_ids, c("F", "R"), qc_steps, target_stats, "Experimental Samples: Forward");

###############################################################################



###############################################################################

cat("Done.\n")
print(warnings());

q(status=0)
