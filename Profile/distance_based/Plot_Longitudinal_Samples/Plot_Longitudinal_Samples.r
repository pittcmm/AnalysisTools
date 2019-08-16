#!/usr/bin/env Rscript

###############################################################################

library(MASS);
library(vegan);
library('getopt');

params=c(
	"input_file", "i", 1, "character",
	"offset_file", "t", 1, "character",
	"output_file", "o", 2, "character",
	"distance_type", "d", 2, "character"
);

opt=getopt(spec=matrix(params, ncol=4, byrow=TRUE), debug=FALSE);
script_name=unlist(strsplit(commandArgs(FALSE)[4],"=")[1])[2];

DEF_DIST="euclidean";

usage = paste(
	"\nUsage:\n", script_name, "\n",
	"	-i <input summary_table.tsv file>\n",
	"	-t <offset file>\n",
	"	-d <distance type, def=", DEF_DIST, ">\n",
	"	[-o <output file root name>]\n",
	"\n",
	"	This script will read in the summary table\n",
	"	and a file describing the time from the first\n",
	"	sample.\n",
	"\n",
	"	The format of the offset file is:\n",
	"\n",
	"	<sample id> \\t <sample grouping/individual id> \\t <time stamp> \\t <cohort (treat/group) id>\\n",
	"\n",
	"	Distance Types:\n",	
	"		euclidean, manhattan, wrd, ...\n",
	"\n");

if(!length(opt$input_file) || !length(opt$offset_file)){
	cat(usage);
	q(status=-1);
}

InputFileName=opt$input_file;
OffsetFileName=opt$offset_file;

if(length(opt$output_file)>0){
	OutputFileRoot=opt$output_file;
}else{
	OutputFileRoot=InputFileName;
	OutputFileRoot=gsub("\\.summary_table\\.tsv$", "", OutputFileRoot);
	OutputFileRoot=gsub("\\.summary_table\\.xls$", "", OutputFileRoot);
	cat("No output file root specified.  Using input file name as root.\n");
}

DistanceType=DEF_DIST;
if(length(opt$distance_type)){
	DistanceType=opt$distance_type;
}

if(DistanceType=="wrd"){
	source("../../SummaryTableUtilities/WeightedRankDifference.r");
}

###############################################################################

OutputFileRoot=paste(OutputFileRoot, ".", substr(DistanceType, 1,3), sep="");

OutputPDF = paste(OutputFileRoot, ".mds_ts.pdf", sep="");
cat("Output PDF file name: ", OutputPDF, "\n", sep="");
pdf(OutputPDF,width=8.5,height=8.5)

###############################################################################

load_offset=function(fname){

        cat("Loading Offsets: ", fname, "\n");
        offsets_mat=read.delim(fname,  header=TRUE, row.names=1, sep="\t", comment.char="#", quote="");

        num_col=ncol(offsets_mat);
        cat("Num Columns Found: ", num_col, "\n");

        extra_colnames=colnames(offsets_mat);
        print(extra_colnames);
        colnames(offsets_mat)=c("Indiv ID", "Offsets", "Group ID", extra_colnames[4:num_col])[1:num_col];

	# Change number IDs to strings
        if(is.numeric(offsets_mat[,"Indiv ID"])){
		numdigits=log10(max(offsets_mat[,"Indiv ID"]))+1;
		prtf_str=paste("%0",numdigits,"d", sep="");
                offsets_mat[,"Indiv ID"]=paste("#",
			 sprintf(prtf_str, offsets_mat[,"Indiv ID"]), sep="");
        }
        groups=unique(offsets_mat[,"Indiv ID"]);

        cat("Groups:\n");
        print(groups);
        cat("\n");

        # Reset offsets so they are relative to the first/smallest sample
        for(gid in groups){
                group_ix=(gid==offsets_mat[,"Indiv ID"]);
                offsets=offsets_mat[group_ix, "Offsets"];
                min_off=min(offsets);
                offsets_mat[group_ix, "Offsets"]=offsets-min_off;
        }

        offsets_data=list();
        offsets_data[["matrix"]]=offsets_mat;
        offsets_data[["IndivID"]]=extra_colnames[1];
        offsets_data[["Offsets"]]=extra_colnames[2];
        offsets_data[["GroupID"]]=extra_colnames[3];

        return(offsets_data);

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

plot_connected_figure=function(coordinates, offsets_mat, groups_per_plot=3, col_assign, ind_colors, title=""){
	sorted_sids=sort(rownames(offsets_mat));
	coordinates=coordinates[sorted_sids,];
	offsets_mat=offsets_mat[sorted_sids,];

	#print(offsets_mat);
	#print(coordinates);

	# Get Unique Groups
	groups=sort(unique(offsets_mat[,"Indiv ID"]));
	num_groups=length(groups);

	palette(ind_colors);

	# Get limits of points
	extra_margin=.2;
	x_range=range(coordinates[,1]);
	y_range=range(coordinates[,2]);
	x_ext=abs(x_range[2]-x_range[1]);
	y_ext=abs(y_range[2]-y_range[1]);
	xlim=c(x_range[1]-x_ext*extra_margin, x_range[2]+x_ext*extra_margin);
	ylim=c(y_range[1]-y_ext*extra_margin, y_range[2]+y_ext*extra_margin);
	cat("\nPoint ranges:\n");
	cat("X:\n");
	print(x_range);
	cat("Y:\n");
	print(y_range);
	cat("Plot ranges:\n");
	cat("X:\n");
	print(xlim);
	cat("Y:\n");
	print(ylim);
	cat("\n");

	# Plot all samples
	plot(0, main=title, xlab="Dim 1", ylab="Dim 2", type="n", xlim=xlim, ylim=ylim);
	for(i in 1:num_groups){
		grp_subset=which(offsets_mat[,"Indiv ID"]==groups[i]);
		num_members=length(grp_subset);
		print(grp_subset);

		offsets_subset=offsets_mat[grp_subset,, drop=F];
		coord_subset=coordinates[grp_subset,, drop=F];

		sort_ix=order(offsets_subset[,"Offsets"], decreasing=F);

		offsets_subset=offsets_subset[sort_ix,, drop=F];
		coord_subset=coord_subset[sort_ix,, drop=F];

		#print(offsets_subset);
		#print(coord_subset);

		#--------------------------------------------------------------------------------
			
		# Draw colored lines
		points(coord_subset, type="l", col=col_assign[groups[i]], pch=20, lwd=2.5);
		# Draw reinforcement black lines
		points(coord_subset, type="b", col="black", pch=20, cex=.1);
		# Draw start/stop glyphs
		points(coord_subset[c(1, 1, num_members),], type="p", col=col_assign[groups[i]], 
			pch=c(17, 1, 15), cex=c(1, 2, 1.25));
	}

	# Plot subset of samples
	for(i in 1:num_groups){
		if(((i-1) %% groups_per_plot)==0){
			plot(0, main=title, xlab="Dim 1", ylab="Dim 2", type="n", xlim=xlim, ylim=ylim);
		}

		#cat("Plotting: ", groups[i], "\n");
		grp_subset=which(offsets_mat[,"Indiv ID"]==groups[i]);
		num_members=length(grp_subset);
		#print(grp_subset);

		offsets_subset=offsets_mat[grp_subset,, drop=F];
		coord_subset=coordinates[grp_subset,, drop=F];

		sort_ix=order(offsets_subset[,"Offsets"], decreasing=F);

		offsets_subset=offsets_subset[sort_ix,, drop=F];
		coord_subset=coord_subset[sort_ix,, drop=F];
			
		#--------------------------------------------------------------------------------
		# Draw colored lines
		points(coord_subset, type="l", col=col_assign[groups[i]], pch=20, cex=.5, lwd=2.5);
		# Draw reinforcement black lines
		points(coord_subset, type="l", col="black", lwd=.1);
		# Draw start/stop glyphs
		points(coord_subset[c(1, 1, num_members),], type="p", col=col_assign[groups[i]], 
			pch=c(17, 1, 15), cex=c(1, 2, 1.25));
		# Label individual id
		text(coord_subset[1,1], coord_subset[1,2], labels=groups[i], col="black", pos=1, cex=.75, font=2);

		# Label offsets
		if(num_members>1){
			offset_ix=2:num_members;
			text(coord_subset[offset_ix,1], coord_subset[offset_ix,2], 
				labels=offsets_subset[offset_ix,"Offsets"], col="black", 
				adj=c(.5,-.75), cex=.5, font=3);
		}
	}
}

###############################################################################

plot_sample_distances=function(distmat, offsets_mat, col_assign, ind_colors, title="", dist_type=""){
	sorted_sids=sort(rownames(offsets_mat));
	offsets_mat=offsets_mat[sorted_sids,];

	# Get Unique Groups
	indiv_ids=sort(unique(offsets_mat[,"Indiv ID"]));
	num_indiv=length(indiv_ids);

	palette(ind_colors);

	def_par=par(no.readonly=T);
	par(mfrow=c(4,1));

	# Get range of offsets
	offset_ranges=range(offsets_mat[,"Offsets"]);
	cat("Offset Range:\n");
	print(offset_ranges);

	#print(offsets_mat);
	distmat2d=as.matrix(distmat);
	dist_ranges=range(distmat2d);
	cat("Distance Ranges:\n");
	print(dist_ranges);

	# Plot subset of samples
	for(i in 1:num_indiv){

		cat("Plotting: ", indiv_ids[i], "\n");
		ind_subset=which(offsets_mat[,"Indiv ID"]==indiv_ids[i]);
		num_samples=length(ind_subset);

		offset_info=offsets_mat[ind_subset,];
		sort_ix=order(offset_info[,"Offsets"]);
		offset_info=offset_info[sort_ix,];
		print(offset_info);

		subset_samples=rownames(offset_info);
		subset_dist=distmat2d[subset_samples[1], subset_samples];
		print(subset_dist);

		# Plot colored lines
		plot(offset_info[,"Offsets"], subset_dist, main=indiv_ids[i],
			 xlab="Time", ylab=paste("Distance (", dist_type, ")", sep=""), 
			type="l", col=col_assign[indiv_ids[i]], lwd=2.5,
			 xlim=offset_ranges, ylim=dist_ranges);
		# Plot ends
		points(offset_info[c(1,1, num_samples),"Offsets"], subset_dist[c(1,1, num_samples)], 
			col=col_assign[indiv_ids[i]],
			type="p", pch=c(17, 1, 15), cex=c(1, 2, 1.25));
		# Plot reinforcement thin black lines
		points(offset_info[,"Offsets"], subset_dist, type="b", pch=16, cex=.1, lwd=.1);
	}
	par(def_par);
}

###############################################################################

plot_sample_dist_by_group=function(dist_mat, offsets_mat, col_assign, ind_colors, dist_type=""){
	
	dist_mat=as.matrix(dist_mat);

        sorted_sids=sort(rownames(offsets_mat));
        offsets_mat=offsets_mat[sorted_sids,, drop=F];

        # Get Num Cohorts
        cohorts=sort(unique(offsets_mat[,"Group ID"]));
        num_cohorts=length(cohorts);
        cat("Number of Cohorts: ", num_cohorts, "\n");
        print(cohorts);
        cat("\n");

        # Get range of offsets
        offset_ranges=range(offsets_mat[,"Offsets"]);
        cat("Offset Range:\n");
        print(offset_ranges);

        # Get range of diversity
        dist_ranges=range(dist_mat);
        cat("Distance Range:\n");
        print(dist_ranges);

        # Set up plots per page
        def_par=par(no.readonly=T);
        par(mfrow=c(num_cohorts,1));

        # Set palette for individuals
        palette(ind_colors);

	x_plot_range=c(offset_ranges[1], offset_ranges[2]+(diff(offset_ranges)/10));

        for(g in 1:num_cohorts){
	
		cat("--------------------------------------------------------------------\n");
                cat("Plotting: ", as.character(cohorts[g]), "\n");
                plot(0, 0, main=cohorts[g],
                         xlab="Time", ylab=paste("Distance (", dist_type, ")", sep=""), type="n",
                         xlim=x_plot_range, ylim=dist_ranges);

                coh_offset_mat=offsets_mat[ offsets_mat[,"Group ID"]==cohorts[g], ];
                print(coh_offset_mat);

                # Get Unique Inidividuals
                indivs=sort(unique(coh_offset_mat[,"Indiv ID"]));
                num_indivs=length(indivs);
                cat("Number of Individuals: ", num_indivs, "\n");
                print(indivs);
                cat("\n");

                # Plot individual samples
                for(i in 1:num_indivs){

                        # Grab from individual cohort 
                        cat("Plotting: ", as.character(indivs[i]), "\n");
                        ind_subset=which(coh_offset_mat[,"Indiv ID"]==indivs[i]);
                        num_timepts=length(ind_subset);

                        # Subset offsets, and sort by offset
                        offset_info=coh_offset_mat[ind_subset,,drop=F];
                        sort_ix=order(offset_info[,"Offsets"]);
                        offset_info=offset_info[sort_ix,];

                        # Subset distances
                        subset_samples=rownames(offset_info);
			subset_dist=dist_mat[subset_samples[1], subset_samples];

                        # Plot distances
                        points(offset_info[c(1,1, num_timepts),"Offsets"], subset_dist[c(1,1, num_timepts)],
                                type="p", pch=c(17, 1, 15), cex=c(1, 2, 1.25), col=col_assign[indivs[i]]);
                        points(offset_info[,"Offsets"], subset_dist, type="l", lwd=2.5, col=col_assign[indivs[i]]);
                        points(offset_info[,"Offsets"], subset_dist, type="l", lwd=.1, col="black");
			text(offset_info[num_timepts, "Offsets"], subset_dist[num_timepts], adj=c(-.5,-1),
				labels=indivs[i], col="black", cex=.5);

                }
        }
        par(def_par);
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

calculate_stats_on_series=function(offset_mat, dist_mat){

	avg_dist=function(dist_arr, time_arr){

		# Average distance sample spent away from home (0)
		num_pts=length(dist_arr);

		acc_dist=0;
		for(i in 1:(num_pts-1)){
			avg_dist=(dist_arr[i+1]+dist_arr[i])/2;
			dtime=(time_arr[i+1]-time_arr[i]);
			acc_dist=acc_dist+avg_dist*dtime;	
		}
		
		overall_avg_dist=acc_dist/time_arr[num_pts];
		return(overall_avg_dist);
	}

	avg_speed=function(dist_arr, time_arr){
		# total distance traveled divided by time
		num_pts=length(dist_arr);
		acc_dist=0;
		for(i in 1:(num_pts-1)){
			ddist=abs(dist_arr[i+1]-dist_arr[i]);
			acc_dist=acc_dist+ddist;
		}
		average_speed=acc_dist/time_arr[num_pts];
		return(average_speed);
	}

	mean_reversion=function(dist_arr, time_arr){
		fit=lm(dist_arr~time_arr);
		res=list();
		res[["first_dist"]]=fit$coefficients[["(Intercept)"]];
		res[["slope"]]=fit$coefficients[["time_arr"]];
		res[["last_dist"]]=res[["first_dist"]]+res[["slope"]]*tail(time_arr,1);
		res[["sd_res"]]=sd(fit$residuals);
		return(res);
	}

	closest_travel=function(dist_arr, time_arr){
		
		dist_arr=dist_arr[-1];
		time_arr=time_arr[-1];

		min_dist=min(dist_arr);
		ix=min(which(min_dist==dist_arr));
		
		res=list();
		res[["dist"]]=min_dist;
		res[["time"]]=time_arr[ix];
		return(res);
	}

	furthest_travel=function(dist_arr, time_arr){
		
		dist_arr=dist_arr[-1];
		time_arr=time_arr[-1];

		max_dist=max(dist_arr);
		ix=min(which(max_dist==dist_arr));
		
		res=list();
		res[["dist"]]=max_dist;
		res[["time"]]=time_arr[ix];
		return(res);
	}

	closest_return=function(dist_arr, time_arr){

		while(length(dist_arr)>1 && dist_arr[1]<=dist_arr[2]){
			dist_arr=dist_arr[-1];
			time_arr=time_arr[-1];
		}
		dist_arr=dist_arr[-1];
		time_arr=time_arr[-1];

                res=list();
		if(length(dist_arr)){
			min_dist=min(dist_arr);
			ix=min(which(min_dist==dist_arr));
			res[["dist"]]=min_dist;
			res[["time"]]=time_arr[ix];
		}else{
			res[["dist"]]=NA;
			res[["time"]]=NA;
		}

                return(res);
	}

	first_return=function(dist_arr, time_arr){

		while(length(dist_arr)>1 && dist_arr[1]<=dist_arr[2]){
			dist_arr=dist_arr[-1];
			time_arr=time_arr[-1];
		}
		dist_arr=dist_arr[-1];
		time_arr=time_arr[-1];

                res=list();
		if(length(dist_arr)){
			res[["dist"]]=dist_arr[1];
			res[["time"]]=time_arr[1];
		}else{
			res[["dist"]]=NA;
			res[["time"]]=NA;
		}

                return(res);
	}


	cat("Calculating average distance over time...\n");

	uniq_indiv_ids=sort(unique(offset_mat[,"Indiv ID"]));
	num_ind=length(uniq_indiv_ids);

	cat("IDs:\n");
	print(uniq_indiv_ids);
	cat("Num Individuals: ", num_ind, "\n");

	stat_names=c(
		"last_time", "num_time_pts",
		"average_dist", 
		"average_speed",
		"mean_reversion_first_dist", "mean_reversion_last_dist", 
		"mean_reversion_stdev_residuals", "mean_reversion_slope",
		"closest_travel_dist", "closest_travel_time",
		"furthest_travel_dist", "furthest_travel_time",
		"closest_return_dist", "closest_return_time",
		"first_return_dist", "first_return_time");

	out_mat=matrix(NA, nrow=num_ind, ncol=length(stat_names));
	rownames(out_mat)=uniq_indiv_ids;
	colnames(out_mat)=stat_names;

	dist_mat=as.matrix(dist_mat);

	for(cur_id in uniq_indiv_ids){
		
		row_ix=(offset_mat[,"Indiv ID"]==cur_id);
		cur_offsets=offset_mat[row_ix,,drop=F];

		# Order offsets
		ord=order(cur_offsets[,"Offsets"]);
		cur_offsets=cur_offsets[ord,,drop=F];

		num_timepts=nrow(cur_offsets);
		out_mat[cur_id, "last_time"]=cur_offsets[num_timepts, "Offsets"];
		out_mat[cur_id, "num_time_pts"]=num_timepts;

		samp_ids=rownames(cur_offsets);

		if(num_timepts>1){
			cur_dist=dist_mat[samp_ids[1], samp_ids];
			cur_times=cur_offsets[,"Offsets"];

			out_mat[cur_id, "average_dist"]=avg_dist(cur_dist, cur_times);
			out_mat[cur_id, "average_speed"]=avg_speed(cur_dist, cur_times);

			res=mean_reversion(cur_dist, cur_times);
			out_mat[cur_id, "mean_reversion_first_dist"]=res[["first_dist"]];
			out_mat[cur_id, "mean_reversion_last_dist"]=res[["last_dist"]];
			out_mat[cur_id, "mean_reversion_stdev_residuals"]=res[["sd_res"]];
			out_mat[cur_id, "mean_reversion_slope"]=res[["slope"]];

			res=closest_travel(cur_dist, cur_times);
			out_mat[cur_id, "closest_travel_dist"]=res[["dist"]];
			out_mat[cur_id, "closest_travel_time"]=res[["time"]];

			res=furthest_travel(cur_dist, cur_times);
			out_mat[cur_id, "furthest_travel_dist"]=res[["dist"]];
			out_mat[cur_id, "furthest_travel_time"]=res[["time"]];

			res=closest_return(cur_dist, cur_times);
			out_mat[cur_id, "closest_return_dist"]=res[["dist"]];
			out_mat[cur_id, "closest_return_time"]=res[["time"]];

			res=first_return(cur_dist, cur_times);
			out_mat[cur_id, "first_return_dist"]=res[["dist"]];
			out_mat[cur_id, "first_return_time"]=res[["time"]];
		}	
	}

	return(out_mat);	
}

###############################################################################

plot_barplot_wsignf_annot=function(title, stat, grps, alpha=0.05, samp_gly=T){
	# Generate a barplot based on stats and groupings
	# Annotat barplot with signficance

	cat("Making Barplot with Significance annotated...\n");
        cat("  Alpha", alpha, "\n");
        group_names=names(grps);
        num_grps=length(group_names);

	# Convert matrix into array, if necessary
	if(!is.null(dim(stat))){
		stat_name=colnames(stat);
		stat=stat[,1];
	}else{
		stat_name="value";
	}

	# Remove NAs
	na_ix=is.na(stat);
	subj=names(stat);
	stat=stat[!na_ix];
	na_subj=names(stat);
	for(grnm in group_names){
		grps[[grnm]]=intersect(grps[[grnm]], na_subj);
		print(stat[grps[[grnm]]]);
	}
	print(grps);

        # Precompute pairwise wilcoxon pvalues
	cat("\n  Precomputing group pairwise p-values...\n");
        pval_mat=matrix(1, nrow=num_grps, ncol=num_grps);
	rownames(pval_mat)=group_names;
	colnames(pval_mat)=group_names;
        signf=numeric();
        for(grp_ix_A in 1:num_grps){
                for(grp_ix_B in 1:num_grps){
                        if(grp_ix_A<grp_ix_B){

				grpAnm=group_names[grp_ix_A];
				grpBnm=group_names[grp_ix_B];

                                res=wilcox.test(stat[grps[[grpAnm]]], stat[grps[[grpBnm]]]);
                                pval_mat[grpAnm, grpBnm]=res$p.value;
                                if(res$p.value<=alpha){
                                        signf=rbind(signf, c(grpAnm, grpBnm, res$p.value));
                                }
                        }
                }
        }

	cat("p-value matrix:\n");
	print(pval_mat);

	# Count how many rows have significant pairings
        num_signf=nrow(signf);
        cat("  Num Significant: ", num_signf, "\n");
        signf_by_row=apply(pval_mat, 1, function(x){sum(x<alpha)});
        cat("  Num Significant by Row:\n");
        print(signf_by_row);

        num_signf_rows=sum(signf_by_row>0);
        cat("  Num Rows to plot:", num_signf_rows, "\n");

        #signf_mat=apply(pval_mat, 1:2,
        #       function(x){
        #               if(x<.001){return("***")}
        #               if(x<.01){return("**")}
        #               if(x<.05){return("*")}
        #               else{return("")}
        #       }
        #);

        #print(signf_mat, quote=F);

        # Compute 95% CI around mean
	cat("\n  Precomputing group means and 95% CI...\n");
        num_bs=320;

        grp_means=numeric(num_grps);
	names(grp_means)=group_names;

        ci95=matrix(NA, nrow=num_grps, ncol=2);
	rownames(ci95)=group_names;
	colnames(ci95)=c("LB", "UB");
        samp_size=numeric(num_grps);
        for(grp_ix in 1:num_grps){

		grpnm=group_names[grp_ix];
                grp_means[grpnm]=mean(stat[grps[[grpnm]]]);
                num_samp=length(grps[[grpnm]]);

                if(num_samp>=40){
                        meds=numeric(num_bs);
                        for(i in 1:num_bs){
                                meds[i]=mean(sample(stat[grps[[grpnm]]], replace=T));

                        }
                        ci95[grp_ix,]=quantile(meds, c(.025, .975));
                }else{
                        ci95[grp_ix,]=rep(mean(stat[grps[[grpnm]]]),2);
                }

                samp_size[grp_ix]=num_samp;
        }

        cat("Group Means:\n");
        print(grp_means);
	print(length(grp_means));
        cat("Group Median 95% CI:\n");
        print(ci95);

        # Estimate spacing for annotations
        annot_line_prop=1/5; # proportion of pl
        min_95ci=min(c(ci95[,1], stat), na.rm=T);
        max_95ci=max(c(ci95[,2], stat), na.rm=T);
	minmax_span=max_95ci-min_95ci;
        plotdatamax=max_95ci+minmax_span*0.3;
	plotdatamin=min_95ci-minmax_span*0.3;;
        space_for_annotations=minmax_span*annot_line_prop*(num_signf_rows+2);
        horiz_spacing=annot_line_prop*plotdatamax;

        # Start plot
        par(mar=c(8,5,4,3));
	cat("  Plot Limits: (", plotdatamin, ", ", plotdatamax, ")\n"); 
	plot(0, type="n", 
		ylim=c(plotdatamin, plotdatamax+space_for_annotations),
		xlim=c(0, num_grps+1),
                yaxt="n", xaxt="n", xlab="", ylab="", bty="n");
	for(grp_ix in 1:num_grps){
		points(c(grp_ix-.25, grp_ix+.25), rep(grp_means[grp_ix],2), type="l", lwd=3);
	}
	mids=1:num_grps;
	yticks=unique(round(seq(min_95ci, max_95ci, length.out=5),1));
	axis(side=2, at=yticks, labels=sprintf("%2.0f", yticks));
        title(ylab=paste("Mean ", stat_name, "\nwith Bootstrapped 95% CI", sep=""));
        title(main=title, cex.main=1.5);
        title(main="with Wilcoxon rank sum test (difference between group means) p-values",
                line=.25, cex.main=.7, font.main=3);

        bar_width=mean(diff(mids));
        qbw=bar_width/6;

	# Label x-axis
        text(mids-par()$cxy[1]/2, rep(6*-par()$cxy[2]/2, num_grps),
                group_names, srt=-45, xpd=T, pos=4,
                cex=min(c(1,.7*bar_width/par()$cxy[1])));

        # Scatter
        if(samp_gly){
                for(grp_ix in 1:num_grps){
			grpnm=group_names[grp_ix];
                        pts=stat[grps[[grpnm]]];
                        numpts=length(pts);
                        points(
                                #rep(mids[grp_ix], numpts),
                                mids[grp_ix]+rnorm(numpts, 0, bar_width/10),
                                pts, col="darkblue", cex=.5, type="p");
                }
        }

        # label CI's
        for(grp_ix in 1:num_grps){
                if(samp_size[grp_ix]>=40){
                        points(
                                c(mids[grp_ix]-qbw, mids[grp_ix]+qbw),
                                rep(ci95[grp_ix, 2],2), type="l", col="blue");
                        points(
                                c(mids[grp_ix]-qbw, mids[grp_ix]+qbw),
                                rep(ci95[grp_ix, 1],2), type="l", col="blue");
                        points(
                                rep(mids[grp_ix],2),
                                c(ci95[grp_ix, 1], ci95[grp_ix,2]), type="l", col="blue");
                }
        }

        # label sample size
        for(grp_ix in 1:num_grps){
                text(mids[grp_ix], 3*-par()$cxy[2]/2, paste("mean =", round(grp_means[grp_ix], 2)), 
			cex=.95, xpd=T, font=3, adj=c(.5,-1));

                text(mids[grp_ix], 4*-par()$cxy[2]/2, paste("n =",samp_size[grp_ix]), 
			cex=.85, xpd=T, font=3, adj=c(.5,-1));
        }

        connect_significant=function(A, B, ypos, pval){
                abline(h=ypos);
        }

        sigchar=function(x){
                if(x<=.0001){
                        return("***");
                }else if(x<=.001){
                        return("**");
                }else if(x<=.01){
                        return("*");
                }else{
                        return("");
                }
        }

        row_ix=1;
        for(i in 1:(num_grps-1)){

                pvalrow=pval_mat[i,];
                #print(pvalrow);

                signf_pairs=(pvalrow<alpha);
                if(any(signf_pairs)){
                        signf_grps=which(signf_pairs);
                        cat("Pairs: ", i, " to:\n");
                        print(signf_grps);

                        y_offset=plotdatamax+horiz_spacing*row_ix;

                        # Draw line between left/reference to each paired signf grp
                        points(c(
                                mids[i], mids[max(signf_grps)]),
                                rep(y_offset,2),
                                type="l", lend="square"
                        );

                        # Mark left/ref group
                        points(
                                rep(mids[i],2),
                                c(y_offset,y_offset-horiz_spacing/4),
                                type="l", lwd=3, lend="butt");

                        # Mark each signf paired reference group
                        for(pair_ix in signf_grps){
                                points(
                                        rep(mids[pair_ix],2),
                                        c(y_offset,y_offset-horiz_spacing/4),
                                        type="l", lwd=1, lend="butt");


                                # label pvalue
                                paird_pval=sprintf("%5.4f", pvalrow[pair_ix]);
                                text(mids[pair_ix], y_offset, paird_pval,
                                        adj=c(.5, -1), cex=.7);
                                text(mids[pair_ix], y_offset, sigchar(pvalrow[pair_ix]),
                                        adj=c(.5, -1.25), cex=1);
                        }

                        row_ix=row_ix+1;

                }

        }
}

###############################################################################

plot_stats_mat=function(sm, grp_map){

	cat("Plotting Stats Matrix...\n");
	num_groups=length(grp_map);
	num_stats=ncol(sm);
	num_indiv=nrow(sm);
	stat_name=colnames(sm);

	cat("Num Groups: ", num_groups, "\n");
	cat("Num Indiv: ", num_indiv, "\n");
	cat("Num Stats: ", num_stats, "\n");

	par(mfrow=c(2,1));

	for(stat_ix in 1:num_stats){
		cat("---------------------------------------------------------\n");
		cat("Plotting: ", stat_name[stat_ix], "\n");
		plot_barplot_wsignf_annot(
			title=stat_name[stat_ix], 
			stat=sm[,stat_ix, drop=F],
			grps=grp_map);
	}

}

###############################################################################

plot_text=function(strings){
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
}

###############################################################################

offset_data=load_offset(OffsetFileName);
offset_mat=offset_data[["matrix"]];

###############################################################################

counts_mat=load_summary_file(InputFileName);
#print(counts_mat);

###############################################################################

offset_mat_samples=rownames(offset_mat);
counts_mat_samples=rownames(counts_mat);
shared=intersect(offset_mat_samples, counts_mat_samples);

cat("Shared:\n");
print(shared);

cat("\n\n");
cat("Samples not represented in offsets file:\n");
print(setdiff(counts_mat_samples, shared));
cat("Samples not represented in summary table file:\n");
print(setdiff(offset_mat_samples, shared));
cat("\n\n");

offset_mat=offset_mat[shared,];
counts_mat=counts_mat[shared,];

###############################################################################

# Get Cohort info
cohort_names=sort(unique(offset_mat[,"Group ID"]));
num_cohorts=length(cohort_names);
cat("Cohorts:\n");
print(cohort_names);
cat("Num Cohorts: ", num_cohorts, "\n");
cat("\n");

# Get Individuals info
indiv_names=sort(unique(offset_mat[,"Indiv ID"]));
num_indiv=length(indiv_names);
cat("Individuals:\n");
print(indiv_names);
cat("Num Individuals: ", num_indiv, "\n");
cat("\n");

###############################################################################

# Assign colors
ind_colors=get_colors(num_indiv);
col_assign=1:num_indiv;
names(col_assign)=indiv_names;

###############################################################################

normalized_mat=normalize(counts_mat);
#print(normalized_mat);

if(DistanceType=="wrd"){
	dist_mat=weight_rank_dist_opt(normalized_mat, 2);
}else{
	dist_mat=vegdist(normalized_mat, method=DistanceType);
}
#dist_mat=dist(normalized_mat);
#print(dist_mat);

# Remove 0 distances with very small number
for(i in 1:length(dist_mat)){
	if(dist_mat[i]==0){
		dist_mat[i]=1e-323;
	}
}

mds_coord=cmdscale(dist_mat, k=2);
isomds=isoMDS(dist_mat);
mds2_coord=isomds$points;

###############################################################################

stats_mat=calculate_stats_on_series(offset_mat, dist_mat);

plot_connected_figure(mds_coord, offset_mat, groups_per_plot=5, col_assign, 
	ind_colors, title=paste("Metric MDS (", DistanceType,")", sep=""));
plot_connected_figure(mds2_coord, offset_mat, groups_per_plot=5, col_assign, 
	ind_colors, title=paste("IsoMetric MDS (", DistanceType, ")", sep=""));

plot_sample_distances(dist_mat, offset_mat, col_assign, ind_colors, 
	dist_type=DistanceType);

plot_sample_dist_by_group(dist_mat, offset_mat, col_assign, ind_colors, 
	dist_type=DistanceType);


# Extract individual membership
uniq_group_ids=sort(unique(offset_mat[,"Group ID"]));
cat("Num Groups: ", length(uniq_group_ids), "\n");
group_map=list();
for(grpid in uniq_group_ids){
	cat("Extracting members of: ", grpid, "\n");
	gix=offset_mat[,"Group ID"]==grpid;
	tmp=sort(unique(offset_mat[gix,"Indiv ID"]));
	group_map[[as.character(grpid)]]=tmp;
}

print(stats_mat);
num_stats=ncol(stats_mat);
cols_per_page=4;
num_pages=ceiling(num_stats/cols_per_page);

cat("Printing Stats to PDF...\n");
cat("Num Stats: ", num_stats, "\n");
cat("Num Pages: ", num_pages, "\n");
cat("Num Stats/Page: ", cols_per_page, "\n");
for(page_ix in 1:num_pages){
	start_col=((page_ix-1)*cols_per_page)+1;
	end_col=min(start_col+cols_per_page-1, num_stats);
	cat("Printing columns: ", start_col, " to ", end_col, "\n", sep="");	
	plot_text(capture.output(print(stats_mat[, start_col:end_col, drop=F])));
}

plot_stats_mat(stats_mat, group_map);

stat_description=c(
	"DESCRIPTION OF STATISTICS:",
	"",
	"",
	"last_time: Last recorded time", 
	"num_time_pts: Number of time points",
	"",
	"average_dist: Average distance samples spent away from 1st sample", 
	"average_speed: (Total changes in distance)/(Last recorded time)",
	"",
	"mean_reversion variables:  Fit linear model across all data points",
	"  mean_reversion_first_dist: expected distance of first sample (y-intercept)", 
	"  mean_reversion_last_dist: expected distance of last sample", 
	"  mean_reversion_stdev_residuals: standard deviation of residuals", 
	"  mean_reversion_slope: slope of linear model",
	"",
	"closest_travel_dist: Distance sample came closest to 1st sample", 
	"closest_travel_time: Time when sample came closest to 1st sample",
	"",
	"furthest_travel_dist: Distance of sample furthest from 1st sample", 
	"furthest_travel_time: Time when sample went furthest from 1st sample",
	"",
	"closest_return_dist: Closest distance sample came to 1st sample after rebounding", 
	"closest_return_time: Time when sample came closest to 1st ample after rebounding",
	"",
	"first_return_dist: Distance when sample first rebounds",
	"first_return_time: Time when sample first rebounds");

par(mfrow=c(1,1));
plot_text(stat_description);

##############################################################################

cat("Done.\n")
dev.off();
warn=warnings();
if(length(warn)){
	print(warn);
}
q(status=0)
