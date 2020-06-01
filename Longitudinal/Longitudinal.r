
extract_offset=function(factor_mat, sbj_cname, timeoffset_cname, start=-Inf, end=Inf){
	
	var_names=colnames(factor_mat);
	if(!any(sbj_cname==var_names)){
		cat("Error: Could not find ", sbj_cname, " in factors.\n");
		quit(status=-1);
	}
	if(!any(timeoffset_cname==var_names)){
		cat("Error: Could not find ", timeoffset_cname, " in factors.\n");
		quit(status=-1);
	}

	offsets_mat=as.data.frame(factor_mat[,c(sbj_cname, timeoffset_cname)]);
	colnames(offsets_mat)=c("SubjectID", "Offsets");

        # Change number IDs to strings
        if(is.numeric(offsets_mat[,"SubjectID"])){
                numdigits=log10(max(offsets_mat[,"SubjectID"]))+1;
                prtf_str=paste("%0",numdigits,"d", sep="");
                offsets_mat[,"SubjectID"]=paste("#",
                         sprintf(prtf_str, offsets_mat[,"SubjectID"]), sep="");
        }else{
		offsets_mat[,"SubjectID"]=as.character(offsets_mat[,"SubjectID"]);
	}

	# Filter offsets by start and end inclusive
	keep_ix=(offsets_mat[, "Offsets"]>=start & offsets_mat[, "Offsets"]<=end)	
	offsets_mat=offsets_mat[keep_ix,];

	cat("Number of Rows in Offset Matrix: ", nrow(offsets_mat), "\n");

        offsets_data=list();
        offsets_data[["matrix"]]=offsets_mat;
        offsets_data[["SampleIDs"]]=sort(rownames(offsets_mat));
        offsets_data[["SubjectIDs"]]=sort(unique(offsets_mat[, "SubjectID"]));
	offsets_data[["NumSubjects"]]=length(offsets_data[["SubjectIDs"]]);
        offsets_data[["Offsets"]]=sort(unique(offsets_mat[, "Offsets"]));
	
	# Offsets by subject
	offsets_by_sbj=list()
	for(sbj in offsets_data[["SubjectIDs"]]){
		sbj_ix=offsets_mat[,"SubjectID"]==sbj;
		offsets_by_sbj[[sbj]]=offsets_mat[sbj_ix,,drop=F];
	}
	offsets_data[["OffsetsBySubject"]]=offsets_by_sbj;

	# Store range information
	if(start==-Inf){
		stag="start";
	}else{
		stag=as.character(start);
	}

	if(end==Inf){
		etag="end";
	}else{
		etag=as.character(end);
	}

	range_tag=paste(stag, "_to_", etag, sep="");
	range_tag=gsub("-", "n", range_tag);

	offsets_data[["RangeTag"]]=range_tag;
	offsets_data[["Start"]]=start;
	offsets_data[["End"]]=end;
	offsets_data[["Earliest"]]=min(offsets_data[["Offsets"]]);
	offsets_data[["Latest"]]=max(offsets_data[["Offsets"]]);
	offsets_data[["Range"]]=offsets_data[["Latest"]]-offsets_data[["Earliest"]];
	offsets_data[["MinOffsetSep"]]=min(diff(offsets_data[["Offsets"]]));
	offsets_data[["NumUniqOffsets"]]=length(offsets_data[["Offsets"]]);
	offsets_data[["OffsetsAsChar"]]=as.character(offsets_data[["Offsets"]]);

	widths=max(ceiling(log10(offsets_data[["Latest"]])+1));
	format=paste("%0",widths+1,".1f", sep="");
	offsets_data[["OffsetsAsCharZeroPad"]]=sprintf(format,offsets_data[["Offsets"]]);

	print(offsets_data);
        return(offsets_data);

}


create_GrpToSbj_map=function(subjects_arr, groups_arr){
        if(length(subjects_arr) != length(groups_arr)){
                cat("Error: Subj/Grp array lengths do no match.\n");
                cat("Subjects:\n");
                print(subjects_arr);
                cat("\nGroups:\n");
                print(groups_arr);
                quit(status=-1);
        }

	# Create subject lookup by group
        uniq_grps=sort(unique(groups_arr));
        grp_to_sbj_map=list();
        for(grp_ix in uniq_grps){
                grp_to_sbj_map[[grp_ix]]=unique(sort(as.character(subjects_arr[groups_arr==grp_ix])));
        }

	# Create map from subject to group
	sbj_to_grp_map=groups_arr;
	names(sbj_to_grp_map)=subjects_arr;

	rec=list();
	rec[["Groups"]]=uniq_grps;
	rec[["NumGroups"]]=length(uniq_grps);
	rec[["GrpToSbj"]]=grp_to_sbj_map;
	rec[["SbjToGrp"]]=sbj_to_grp_map;	

        return(rec);
}


group_offsets=function(offsets_data){
	
	cat("Reorganizing Raw Offset Data...\n");
	mat=offsets_data[["matrix"]];

	indiv_offsets=list();

	indiv_rows=mat[,"Indiv ID"];

	indivs=sort(unique(indiv_rows));
	
	# Groups offsets by individual
	for(indiv_ix in indivs){

		# Extract rows for individual
		rows_ix=(indiv_rows==indiv_ix)
		cur_samp=mat[rows_ix,,drop=F];
	
		# Reorder by offset
		reorder_ix=order(cur_samp[,"Offsets"]);
		cur_samp=cur_samp[reorder_ix,,drop=F];

		# Add column for sample ID from rowname
		samp_ids=rownames(cur_samp);
		cur_samp=cbind(cur_samp, samp_ids);
		colnames(cur_samp)[4]="Samp ID";

		# Store record in list
		indiv_offsets[[indiv_ix]]=cur_samp;
	}

	# Group individuals by Group ID
	grp_info=list();
	grps=as.character(sort(unique(mat[,"Group ID"])));
	for(gr in grps){
		grp_info[[gr]]=as.character(sort(unique(mat[(mat[,"Group ID"]==gr),"Indiv ID"])));
	}
	

	res=list();
	res[["OffsetsByIndiv"]]=indiv_offsets;
	res[["IndivByGrp"]]=grp_info;
	res[["Individuals"]]=indivs;
	res[["Offsets"]]=sort(unique(mat[,"Offsets"]));
	res[["Groups"]]=grps;

	cat("ok.\n");
	return(res);
}

###############################################################################

calculate_stats_on_series_distance=function(offset_rec, dist_mat){

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

        tot_dist_travelled=function(dist_arr, time_arr){
                # total distance traveled
                num_pts=length(dist_arr);
                acc_dist=0;
                for(i in 1:(num_pts-1)){
                        ddist=abs(dist_arr[i+1]-dist_arr[i]);
                        acc_dist=acc_dist+ddist;
                }
                return(acc_dist);
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

        uniq_indiv_ids=offset_rec[["SubjectIDs"]];
        num_ind=offset_rec[["NumSubjects"]];

        stat_names=c(
                "last_time", "num_time_pts",
                "average_dist",
                "average_speed",
                "total_dist_travelled",
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

                cur_offsets=offset_rec[["OffsetsBySubject"]][[cur_id]];
                num_timepts=nrow(cur_offsets);

                out_mat[cur_id, "last_time"]=cur_offsets[num_timepts, "Offsets"];
                out_mat[cur_id, "num_time_pts"]=num_timepts;

                samp_ids=rownames(cur_offsets);

                if(num_timepts>1){
                        cur_dist=dist_mat[samp_ids[1], samp_ids];
                        cur_times=cur_offsets[,"Offsets"];

                        out_mat[cur_id, "average_dist"]=avg_dist(cur_dist, cur_times);
                        out_mat[cur_id, "average_speed"]=avg_speed(cur_dist, cur_times);
                        out_mat[cur_id, "total_dist_travelled"]=tot_dist_travelled(cur_dist, cur_times);

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

calc_longitudinal_stats=function(offset_rec, alr_cat_val){

        cat("Calculating Longitudinal Statistics...\n");

        l_min=function(x, y){
                res=min(y);
                return(res);
        }
        l_max=function(x, y){
                res=max(y);
                return(res);
        }
        l_median=function(x, y){
                res=median(y);
                return(res);
        }
        l_mean=function(x, y){
                res=mean(y);
                return(res);
        }
        l_stdev=function(x, y){
                res=sd(y);
                return(res);
        }
        l_range=function(x, y){
                r=range(y);
                span=abs(r[1]-r[2]);
                return(span);
        }
        l_N=function(x, y){
                return(length(x));
        }
        l_last_time=function(x, y){
                return(max(x));
        }

        l_volatility=function(x, y){
                if(length(x)>1){
                        fit=lm(y~x);
                        sumfit=summary(fit);
                        vol=sd(sumfit$residuals);
                        return(vol);
                }else{
                        return(NA);
                }
        }
        l_slope=function(x, y){
                if(length(x)>1){
                        fit=lm(y~x);
                        slope=fit$coefficients["x"];
                        return(slope);
                }else{
                        return(NA);
                }
        }

        l_time_wght_avg=function(x, y){
                npts=length(x);
                if(npts>1){

                        tot_avg=0;

                        for(i in 1:(npts-1)){
                                avg_val=(y[i]+y[i+1])/2;
                                duration=(x[i+1]-x[i]);
                                tot_avg=tot_avg+(avg_val*duration);
                        }

                        norm=tot_avg/(x[npts]-x[1]);
                        return(norm);
                }else{
                        return(NA);
                }
        }

        l_time_at_max=function(x, y){
                max_val=max(y);
                ix=min(which(y==max_val));
                return(x[ix]);
        }

        l_time_at_min=function(x, y){
                min_val=min(y);
                ix=min(which(y==min_val));
                return(x[ix]);
        }

        l_time_closest_to_t0=function(x, y){
                starty=y[1];
                y=y[-1];
                dist=abs(y-starty);
                min_dist=min(dist);
                min_ix=min(which(min_dist==dist));
                return(x[min_ix+1]);
        }

        l_time_furthest_fr_t0=function(x, y){
                starty=y[1];
                y=y[-1];
                dist=abs(y-starty);
                max_dist=max(dist);
                max_ix=min(which(max_dist==dist));
                return(x[max_ix+1]);
        }

        l_start_end_diff=function(x,y){
                start=y[1];
                end=tail(y,1);
                return(end-start);
        }

        l_convexcave=function(x, y){
                num_pts=length(x);
                # y=mx+b
                # b=y-mx

                m=(y[num_pts]-y[1])/(x[num_pts]-x[1]);
                b=y[1]-m*x[1];

                lvl_y=numeric(num_pts);
                for(i in 1:num_pts){
                        lvl_y[i]=y[i]-(m*x[i]+b);
                }

                cum_sum=0;
                for(i in 1:(num_pts-1)){
                        dx=x[i+1]-x[i];
                        avgy=(lvl_y[i+1]+lvl_y[i])/2;
                        avg=dx*avgy/2;
                        cum_sum=cum_sum+avg;
                }
                vexcav=cum_sum/(x[num_pts]-x[1]);

                return(vexcav);
        }


        # statistic:
        #    ALR:
        #       individual:

        stat_name=c(
                "min", "max", "range",
                "volatility", "slope", "time_wght_avg",
                "time_at_max", "time_at_min",
                "time_closest_to_t0", "time_furthest_fr_t0",
                "start_end_diff",
                "convexcave"
        );

        results=list();

        alrcat=colnames(alr_cat_val);
        individuals=as.character(offset_rec[["SubjectIDs"]]);

        cat("\n");
        cat("Individuals:\n");
        print(individuals);

        cat("\n");
        cat("Categories:\n");
        print(alrcat);

        num_cat=ncol(alr_cat_val);
        num_ind=length(individuals);


        for(stat_ix in stat_name){

                results[[stat_ix]]=list();

                tmp_mat=matrix(NA, nrow=num_ind, ncol=num_cat);
                rownames(tmp_mat)=individuals;
                colnames(tmp_mat)=alrcat;

                for(cat_ix in alrcat){

                        for(ind_ix in individuals){

                                indv_offsets=offset_rec[["OffsetsBySubject"]][[ind_ix]];
                                samp_ids=rownames(indv_offsets);

                                time=indv_offsets[,"Offsets"];
                                val=alr_cat_val[samp_ids, cat_ix];

                                funct_name=paste("l_", stat_ix, sep="");

                                call_res=do.call(funct_name, list(x=time, y=val));

                                tmp_mat[ind_ix, cat_ix]=call_res;

                        }

                }

                results[[stat_ix]]=tmp_mat;

        }

        return(results);
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

				grpAval=stat[grps[[grpAnm]]];
				grpBval=stat[grps[[grpBnm]]];

				grpAmean=mean(grpAval);
				grpBmean=mean(grpBval);

                                res=wilcox.test(grpAval, grpBval);
                                pval_mat[grpAnm, grpBnm]=res$p.value;
                                if(res$p.value<=alpha){
                                        signf=rbind(signf, 
						c(grpAnm, sprintf("%8.4f",grpAmean), 
						grpBnm, sprintf("%8.4f",grpBmean), 
						sprintf("%8.4f", (grpBmean-grpAmean)),
						sprintf("%5.3f",res$p.value)));
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

        yticks=seq(min_95ci, max_95ci, length.out=5);
        cat("Y ticks:\n");
        print(yticks);
        signf_digits=max(ceiling(abs(log10(abs(yticks)))));
        yticks=signif(yticks, signf_digits);

        axis(side=2, at=yticks, labels=sprintf("%3.2f", yticks), cex.axis=.5, las=2);
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
	
	return(signf);

}

