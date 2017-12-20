#!/usr/bin/env Rscript

###############################################################################

library(MASS);
library(vegan);
library('getopt');

params=c(
	"input_file", "i", 1, "character",
	"factor_file", "f", 2, "character",
	"top_categories", "t", 2, "character",
	"output_file", "o", 2, "character",
	"diversity_type", "d", 2, "character"
);

opt=getopt(spec=matrix(params, ncol=4, byrow=TRUE), debug=FALSE);
script_name=unlist(strsplit(commandArgs(FALSE)[4],"=")[1])[2];

DEF_DIVERSITY="tail";
TOP_CATEGORIES=4;

usage = paste(
	"\nUsage:\n", script_name, "\n",
	"	-i <input summary_table.tsv file>\n",
	"	[-f <factor file>]\n",
	"	[-t <top categories to display, default=", TOP_CATEGORIES, ">]\n",
	"	[-o <output file root name>]\n",
	"	[-d <diversity, default=", DEF_DIVERSITY, ".]\n",
	"\n",
	"	This script will read in the summary table\n",
	"	and the factor file.\n",
	"\n",
	"	For each factor (column), a set of stacked\n",
	"	barplots will be generated for each factor level\n",
	"	If there is no factor file specified, then\n",
	"	then the average distribution will be plotted\n",
	"\n",
	"	Diversity types include:\n",
	"		shannon, tail, simpson, invsimpson\n",
	"\n",
	"	Each stacked barplot will be labeled with median and 95%CI\n",
	"	of the diversity index\n",
	"\n",
	"\n", sep="");

if(!length(opt$input_file) || !length(opt$factor_file)){
	cat(usage);
	q(status=-1);
}

InputFileName=opt$input_file;
FactorFileName=opt$factor_file;

DiversityType=DEF_DIVERSITY;
if(length(opt$diversity_type)){
	DiversityType=opt$diversity_type;
}

NumTopCategories=TOP_CATEGORIES;
if(length(opt$top_categories)){
	NumTopCategories=opt$top_categories;
}

if(length(opt$output_file)>0){
	OutputFileRoot=opt$output_file;
}else{
	OutputFileRoot=InputFileName;
	OutputFileRoot=gsub("\\.summary_table\\.tsv$", "", OutputFileRoot);
	OutputFileRoot=gsub("\\.summary_table\\.xls$", "", OutputFileRoot);
	cat("No output file root specified.  Using input file name as root.\n");
}

###############################################################################

OutputFileRoot=paste(OutputFileRoot, ".", substr(DiversityType, 1, 4), sep="");
OutputPDF = paste(OutputFileRoot, ".div_ts.pdf", sep="");
cat("Output PDF file name: ", OutputPDF, "\n", sep="");
pdf(OutputPDF,width=8.5,height=14)

###############################################################################

load_factors=function(fname){
        factors=data.frame(read.table(fname,  header=TRUE, check.names=FALSE, row.names=1, comment.char="", quote="", sep="\t"));
        dimen=dim(factors);
        cat("Rows Loaded: ", dimen[1], "\n");
        cat("Cols Loaded: ", dimen[2], "\n");
        return(factors);
}

load_summary_file=function(fname){
        cat("Loading Summary Table: ", fname, "\n");
        inmat=as.matrix(read.table(fname, sep="\t", header=TRUE, check.names=FALSE, comment.char="", row.names=1))
        counts_mat=inmat[,2:(ncol(inmat))];
        return(counts_mat);
}

normalize=function(counts){
        totals=apply(counts, 1, sum);
        num_samples=nrow(counts);
        normalized=matrix(0, nrow=nrow(counts), ncol=ncol(counts));

        for(i in 1:num_samples){
                normalized[i,]=counts[i,]/totals[i];
        }

        colnames(normalized)=colnames(counts);
        rownames(normalized)=rownames(counts);
        return(normalized);
}

simplify_matrix_categories=function(normalized_mat, top=4){
	# This function will reduce the matrix to only contain
	# the categories that are in the top n across all of the
	# samples.  This way, all of the categories will be represented
	# to some extent.  The returned matrix will have its
	# columns sorted by decreasing abundance.

	keep_cat=character();
	num_samp=nrow(normalized_mat);
	samp_names=rownames(normalized_mat);
	
	for(i in 1:num_samp){
		#cat(samp_names[i], "\n");
		abund=sort(normalized_mat[i,], decreasing=T);
		top_cat=(names(abund)[1:top]);	
		#print(top_cat);
		#cat("\n");
		keep_cat=c(keep_cat, top_cat);
	}

	uniq_keep_cat=unique(keep_cat);
	cat("Top ", top, " across all samples:\n", sep="");
	print(uniq_keep_cat);

	# Keep categories across top categories
	keep_mat=normalized_mat[,uniq_keep_cat];

	# Sort categories in decreasing order
	avg_abund=apply(keep_mat, 2, mean);
	sort_ix=order(avg_abund, decreasing=T);
	keep_mat=keep_mat[, sort_ix];
	return(keep_mat);
	
}

plot_text=function(strings){

	orig.par=par(no.readonly=T);
        par(family="Courier");
        par(oma=rep(.1,4));
        par(mar=rep(0,4));

        num_lines=length(strings);

        top=max(as.integer(num_lines), 52);

        plot(0,0, xlim=c(0,top), ylim=c(0,top), type="n",  xaxt="n", yaxt="n",
                xlab="", ylab="", bty="n", oma=c(1,1,1,1), mar=c(0,0,0,0)
                );

        text_size=max(.01, min(.8, .8 - .003*(num_lines-52)));
        #print(text_size);

        for(i in 1:num_lines){
                #cat(strings[i], "\n", sep="");
                strings[i]=gsub("\t", "", strings[i]);
                text(0, top-i, strings[i], pos=4, cex=text_size);
        }

	par(orig.par);
}

###############################################################################

# Get color assignments
get_colors=function(num_col, alpha=1){
	colors=hsv(seq(0,1,length.out=num_col+1), c(1,.5), c(1,.75,.5), alpha=alpha);
	color_mat_dim=ceiling(sqrt(num_col));
	color_pad=rep("grey", color_mat_dim^2);
	color_pad[1:num_col]=colors[1:num_col];
	color_mat=matrix(color_pad, nrow=color_mat_dim, ncol=color_mat_dim);
	colors=as.vector(t(color_mat));
	colors=colors[colors!="grey"];
}

###############################################################################

plot_dist=function(x, y, width=20, abundances){
	# This function will plot a stack box plot
	# The location is center around x, and over y, with a bar height of 1
	
	rect(
		xleft=x-width/2,
		ybottom=0,
		xright=x+width/2,
		ytop=1,
		lwd=.01,
		col="grey"
	);

	num_abund=length(abundances);
	prev=0;
	for(i in 1:num_abund){
		rect(
			xleft=x-width/2,
			ybottom=prev,
			xright=x+width/2,
			ytop=prev+abundances[i],
			lwd=.01,
			col=i
		);	
		prev=prev+abundances[i];
	}
		
}

plot_legend=function(categories){
	orig.par=par(no.readonly=T);
	par(mar=c(0,0,0,0));
	num_cat=length(categories);
	plot(0,0, type="n", ylim=c(-10,0), xlim=c(0,30), bty="n", xaxt="n", yaxt="n");
	legend(0,0, legend=rev(c(categories, "Remaining")), fill=rev(c(1:num_cat, "grey")), cex=.7);
	par(mar=orig.par$mar);
}



###############################################################################

tail_statistic=function(x){
        sorted=sort(x, decreasing=TRUE);
        norm=sorted/sum(x);
        n=length(norm);
        tail=0;
        for(i in 1:n){
                tail=tail + norm[i]*((i-1)^2);
        }
        return(sqrt(tail));
}

###############################################################################

plot_abundance_matrix=function(abd_mat, title="", plot_cols=8, plot_rows=4, samp_size=c(), divname=c(), diversity=c()){
	# This function will plot a sample x abundance (summary table)
	# There will be one plot for row (sample) in the matrix

	num_cat=ncol(abd_mat);
	num_samples=nrow(abd_mat);
	sample_names=rownames(abd_mat);
	cat_names=colnames(abd_mat);
	label_samp_size=(length(samp_size)>0);
	label_diversity=(length(diversity)>0);

	# Set up layout
	tot_plots_per_page=plot_cols*plot_rows;
	layout_mat=matrix(1:tot_plots_per_page, byrow=T, nrow=plot_rows, ncol=plot_cols);
	layout_mat=rbind(layout_mat, rep(tot_plots_per_page+1, plot_cols));
	layout_mat=rbind(layout_mat, rep(tot_plots_per_page+1, plot_cols));
	#cat("Layout Matrix:\n");
	#print(layout_mat);
	layout(layout_mat);

	orig.par=par(no.readonly=T);
	par(oma=c(.5,.5,3.5,.5));
	par(mar=c(1,1,1,1));

	i=0;
	while(i<num_samples){
		for(y in 1:plot_rows){
			for(x in 1:plot_cols){
				if(i<num_samples){
					sample=sample_names[i+1];
					plot(0,0, c(-1,1), ylim=c(0,1), type="n", bty="n", xaxt="n", yaxt="n");

					mtext(sample, line=0, cex=.5, font=2);

					if(label_samp_size){
						n=samp_size[i+1];
						mtext(paste("n=",n,sep=""), line=-.5, cex=.4, font=3);
					}
					if(label_diversity){
						text(0-.7, 0, paste(divname[i+1]," = ",signif(diversity[i+1], 4),sep=""),
							srt=90, adj=0, cex=.7);
					}

					abundances=abd_mat[sample,,drop=F];
					plot_dist(0, 0, width=1, abundances);
				}else{
					plot(0,0, c(-1,1), ylim=c(0,1), type="n", bty="n", xaxt="n", yaxt="n");
				}
				i=i+1;
			}
		}
		cat("Plotting legend...\n");
		plot_legend(cat_names);
		mtext(text=title, side=3, outer=T, cex=2, font=2, line=.5);
	}
	par(orig.par);
}

###############################################################################

orig_factors_mat=load_factors(FactorFileName);
#print(factors_mat);

###############################################################################

orig_counts_mat=load_summary_file(InputFileName);
#print(counts_mat);

###############################################################################

orig_factors_samples=rownames(orig_factors_mat);
orig_counts_samples=rownames(orig_counts_mat);
shared=intersect(orig_factors_samples, orig_counts_samples);

cat("\n\n");
cat("Samples not represented in summary table file:\n");
excl_to_st=setdiff(orig_counts_samples, shared);
print(excl_to_st);
cat("Samples not represented in offsets file:\n");
excl_to_fct=setdiff(orig_factors_samples, shared);
print(excl_to_fct);
cat("\n\n");

num_shared=length(shared);
cat("Number of Shared Samples: ", num_shared, "\n");

factors_mat=orig_factors_mat[shared,];
counts_mat=orig_counts_mat[shared,];

###############################################################################

normalized_mat=normalize(counts_mat);
#print(normalized_mat);

# simplify matrix
simplified_mat=simplify_matrix_categories(normalized_mat, top=NumTopCategories);
num_simp_cat=ncol(simplified_mat);
cat("Number of Simplified Abundances: ", num_simp_cat, "\n");

if(DiversityType=="tail"){
	diversity_arr=apply(normalized_mat, 1, tail_statistic);
}else{
	diversity_arr=diversity(normalized_mat, DiversityType);
}
cat("Diversity:\n");
print(diversity_arr);

plot_text(c(
	paste("Summary Table File: ", InputFileName),
	paste("Factor File: ", FactorFileName),
	"",
	paste("Diversity Index:", DiversityType),
	"",
	"Summary Table:",
	paste("    Num Samples:", nrow(orig_counts_mat)),
	paste(" Num Categories:", ncol(orig_counts_mat)),
	"",
	"Factor Table:",
	paste("    Num Samples:", nrow(orig_factors_mat)),
	paste("    Num Factors:", ncol(orig_factors_mat)),
	"",
	paste("Shared Samples:", num_shared),
	"",
	paste("Number of Top Categories from each sample to summarize:", NumTopCategories),
	paste("Number of Unique Categories across top categories extracted:", num_simp_cat),
	"",
	"Samples exclusive to Summary Table:",
	capture.output(print(excl_to_st)),
	"",
	"Samples exclusive to Factor Table:",
	capture.output(print(excl_to_fct))
));

###############################################################################

category_colors=get_colors(num_simp_cat);
palette(category_colors);

plot_abundance_matrix(simplified_mat, title="By Sample ID", divname=rep(DiversityType, num_shared), diversity=diversity_arr);

###############################################################################

map_val_to_grp=function(fact_mat){
	# This function will convert a factor matrix, into
	# a grouping matrix to reduce the number of continous values

	num_factors=ncol(factors_mat);
	num_values=nrow(factors_mat);
	fact_names=colnames(factors_mat);
	map_mat=as.data.frame(fact_mat);

	for(fidx in 1:num_factors){
		fact_name=fact_names[fidx];
		cat("\nMapping on: ", fact_name, "\n");

		fact_val=factors_mat[,fidx];
		print(fact_val);
		non_na_ix=!is.na(fact_val);
		fact_val=fact_val[non_na_ix];
		num_fact_val=length(fact_val);

		if(is.factor(fact_val)){
			cat(fact_name, " is a factor.\n", sep="");
			fact_lev=levels(fact_val);
			print(fact_lev);
		}else{
			unique_val=unique(fact_val);
			num_unique=length(unique_val);

			if(num_unique<=2){
				cat(fact_name, ": few enough unique values, NOT grouping\n", sep="");
				map_mat[,fidx]=as.character(map_mat[,fidx]);
			}else{
				cat(fact_name, ": too many unique values, grouping...\n", sep="");
				hist_res=hist(fact_val,breaks=nclass.Sturges(fact_val), plot=F);
				cat("Values\n");
				print(fact_val);
				num_grps=length(hist_res$breaks);
				cat("Num Groups: ", num_grps, "\n");
				grp_levels=paste(hist_res$breaks[1:(num_grps-1)], "-", hist_res$breaks[2:num_grps], sep="");
				cat("Group:\n");
				print(grp_levels);

				grp_asn=character(num_fact_val);
				lowerbounds=hist_res$breaks[1:(num_grps-1)];
				for(i in 1:num_fact_val){
					grp_asn[i]=grp_levels[max(which(fact_val[i]>=lowerbounds))];
					#cat(fact_val[i], "->", grp_levels[grp_asn[i]],"\n");	
				}
				cat("Assigned Groups:\n");
				print(grp_asn);

				# Convert strings to factors
				grp_as_factor=factor(grp_asn, levels=grp_levels, ordered=F);
				# Initialize an array
				tmp=rep(grp_as_factor[1],num_values);
				# Copy values over
				tmp[non_na_ix]=grp_asn;
				# Replace NAs
				tmp[setdiff(1:num_values, which(non_na_ix))]=NA;
				map_mat[,fidx]=tmp;
			}

			cat("Unique Val:", unique_val, "\n");
		
		}	
	}
	return(map_mat);
}

###############################################################################
# Plot stacked bar plots across each of the factors

grp_mat=map_val_to_grp(factors_mat);
print(grp_mat);

sample_names=rownames(grp_mat);
grp_names=colnames(grp_mat);
for(i in 1:ncol(grp_mat)){
		
	values=(grp_mat[,i]);
	all_levels=levels(values);
	groups=sort(unique(values[!is.na(values)]));
	grp_name=grp_names[i];
	num_grps=length(groups);

	cat("Plotting: ", grp_name, "\n");
	cat("Available Groups: \n");
	print(groups);

	cat("Num Available Groups: ", num_grps, "\n");
	cat("Possible Groups (levels): \n");
	print(all_levels);

	combined_abd=matrix(0, nrow=num_grps, ncol=num_simp_cat);
	rownames(combined_abd)=groups;
	colnames(combined_abd)=colnames(simplified_mat);
	sample_sizes=numeric(num_grps);
	grp_div=numeric(num_grps);
	divname=character(num_grps);
	grp_i=1;
	for(grp in groups){
		cat("Extracting: ", grp, "\n");
		samp_ix=(which(grp==values));
		sample_sizes[grp_i]=length(samp_ix);
		sample_arr=sample_names[samp_ix];

		if(sample_sizes[grp_i]>1){
			grp_div[grp_i]=median(diversity_arr[sample_arr]);
			divname[grp_i]=paste("median ", DiversityType, sep="");
		}else{
			grp_div[grp_i]=diversity_arr[sample_arr];
			divname[grp_i]=DiversityType;
		}

		combined_abd[grp,]=apply(simplified_mat[sample_arr,,drop=F], 2, mean);
		#print(combined_abd);	
		grp_i=grp_i+1;
	}
	#print(combined_abd);
	#print(sample_sizes);
	plot_abundance_matrix(combined_abd, title=grp_name, samp_size=sample_sizes, 
		divname=divname, diversity=grp_div);

	cat("\n");
	
}

###############################################################################

cat("Done.\n")
dev.off();
warn=warnings();
if(length(warn)){
	print(warn);
}
q(status=0)
