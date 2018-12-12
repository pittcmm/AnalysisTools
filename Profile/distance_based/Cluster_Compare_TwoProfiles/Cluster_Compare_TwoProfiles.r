#!/usr/bin/env Rscript

###############################################################################

cat("\n\n");

library(MASS)
library('getopt');
library('vegan');
library('plotrix');


DEF_DISTTYPE="man";

params=c(
	"input_summary_table_A", "a", 1, "character",
	"input_summary_table_B", "b", 1, "character",
	"mapping_file", "m", 1, "character",
	"output_filename_root", "o", 1, "character",
	"dist_type", "d", 2, "character"
);

opt=getopt(spec=matrix(params, ncol=4, byrow=TRUE), debug=FALSE);
script_name=unlist(strsplit(commandArgs(FALSE)[4],"=")[1])[2];

usage = paste(
	"\n\nUsage:\n", script_name, "\n",
	"	-a <input summary_table.tsv file A>\n",
	"	-b <input summary_table.tsv file B>\n",
	"	-m <mapping file, from A to B Identifiers>\n",
	"	-o <output file root name>\n",
	"\n",
	"	Options:\n",
	"	[-d <euc/wrd/man/bray/horn/bin/gow/tyc/minkp5/minkp3, default =", DEF_DISTTYPE, ">]\n",
	"\n",
	"This script will compute distance matrices for the two summary tables independently, then\n",
	"compare them using Mantel's statistic.  The summary tables do not have to have matching\n",
	"categories.\n",
	"\n\n",
	"The mapping file must be specified so that the sample IDs can be paired up.\n",
	"The first row of each column in the mapping file will be used in the analyses.\n",
	"Eg.:\n",
	"\n",
	"<sample group A name>\\t<sample group B name>\n",
	"<id.A.1>\\t<id.B.1>\n",
	"<id.A.2>\\t<id.B.2>\n",
	"<id.A.3>\\t<id.B.3>\n",
	"...\n",
	"<id.A.N>\\t<id.B.N>\n",
	
	"\n\n",
	"For the distance types:\n",
	" minkp5 is the minkowski with p=.5, i.e. sum((x_i-y_i)^1/2)^2\n",
	" minkp3 is the minkowski with p=.3, i.e. sum((x_i-y_i)^1/3)^3\n",
	"\n");

if(
	!length(opt$input_summary_table_A) || 
	!length(opt$input_summary_table_B) || 
	!length(opt$mapping_file) || 
	!length(opt$output_filename_root) 
){
	cat(usage);
	q(status=-1);
}

InputSumTabA=opt$input_summary_table_A;
InputSumTabB=opt$input_summary_table_B;
MappingFile=opt$mapping_file;
OutputFileRoot=opt$output_filename_root;

DistType=DEF_DISTTYPE;
if(length(opt$dist_type)){
	DistType=opt$dist_type;
}


if(!any(DistType== c("wrd","man","bray","horn","bin","gow","euc","tyc","minkp3","minkp5"))){
	cat("Error: Specified distance type: ", DistType, " not recognized.\n");
	quit(status=-1);
}

###############################################################################

cat("Input Summary Table A:", InputSumTabA, "\n");
cat("Input Summary Table B:", InputSumTabB, "\n");
cat("Mapping File         :", MappingFile, "\n");
cat("Output File          :", OutputFileRoot, "\n");
cat("Distance Type        :", DistType, "\n");

###############################################################################
# See http://www.mothur.org/wiki/Thetayc for formula

tyc_fun=function(v1, v2){
	sum_intersect=sum(v1*v2);
	sum_sqrd_diff=sum((v1-v2)^2);
	denominator=sum_sqrd_diff + sum_intersect;
	tyc=1-(sum_intersect/denominator);
	return(tyc);
}

thetaYC=function(matrix){
	
	nsamples=nrow(matrix);
	ycdist=matrix(0, ncol=nsamples, nrow=nsamples);
	for(i in 1:nsamples){
		for(j in 1:nsamples){
			if(i<j){
				ycdist[i,j]=tyc_fun(matrix[i,], matrix[j,]);
			}else{
				ycdist[i,j]=ycdist[j,i];			
			}
		}
	}
	
	as.dist(return(ycdist));
}

weight_rank_dist_opt=function(M, deg){
        NumSamples=nrow(M);
        order_matrix=matrix(0, nrow=nrow(M), ncol=ncol(M));
        for(i in 1:NumSamples){
                order_matrix[i,]=rank(M[i,], ties.method="average");
        }

        dist_mat=matrix(0, nrow=NumSamples, ncol=NumSamples);
        colnames(dist_mat)=rownames(M);
        rownames(dist_mat)=rownames(M);
        for(i in 1:NumSamples){
                for(j in 1:i){
                        dist_mat[i,j]=
                                sqrt(sum((
                                        (order_matrix[i,]-order_matrix[j,])^2)*
                                        (((M[i,]+M[j,])/2)^deg)
                                        )
                                );
                }
        }
        return(as.dist(dist_mat));

}


###############################################################################

load_summary_table=function(st_fname){
	inmat=as.matrix(read.delim(st_fname, sep="\t", header=TRUE, row.names=1, check.names=FALSE, comment.char="", quote=""))

	num_categories=ncol(inmat)-1;
	num_samples=nrow(inmat);

	cat("Loaded Summary Table: ", st_fname, "\n", sep="");
	cat("  Num Categories: ", num_categories, "\n", sep="");
	cat("  Num Samples: ", num_samples, "\n", sep="");

	countsmat=inmat[,2:(num_categories+1)];

	return(countsmat);
}

#------------------------------------------------------------------------------

load_mapping_file=function(mp_fname, keep_a_ids, keep_b_ids){

	num_keep_a=length(keep_a_ids);
	num_keep_b=length(keep_b_ids);
	cat("Num A's IDs to keep: ", num_keep_a, "\n");
	cat("Num B's IDs to keep: ", num_keep_b, "\n");

	inmat=as.matrix(read.delim(mp_fname, sep="\t", header=TRUE, check.names=F, comment.char="", quote=""));

	# Keep Entry if record is in both lists
	keep_ix=c();
	orig_mat_rows=nrow(inmat);
	cat("Number of Mapping Entries Read: ", orig_mat_rows, "\n");
	for(i in 1:orig_mat_rows){
		if(any(inmat[i,1]==keep_a_ids) && any(inmat[i,2]==keep_b_ids)){
			keep_ix=c(keep_ix, i);
		}
	}
	inmat=inmat[keep_ix,];
	num_kept_matrows=nrow(inmat);
	cat("Number of Mapping Entries Kept: ", num_kept_matrows, "\n");

	mapping=as.list(x=inmat[,1]);
	names(mapping)=inmat[,2];

	coln=colnames(inmat);
	map_info=list();
	map_info[["map"]]=mapping;
	map_info[["a"]]=coln[1];
	map_info[["b"]]=coln[2];
	map_info[["a_id"]]=inmat[,1];
	map_info[["b_id"]]=inmat[,2];

	return(map_info);	
}

#------------------------------------------------------------------------------

normalize=function(st){
	num_samples=nrow(st);
	num_categories=ncol(st);

	normalized=matrix(0, nrow=num_samples, ncol=num_categories);
	colnames(normalized)=colnames(st);
	rownames(normalized)=rownames(st);

	sample_counts=apply(st, 1, sum);
	for(i in 1:num_samples){
		normalized[i,]=st[i,]/sample_counts[i];
	}
	return(normalized);
}

#------------------------------------------------------------------------------

compute_dist=function(norm_st, type){

	if(type=="euc"){
		dist_mat=dist(norm_st);
	}else if (type=="wrd"){
		dist_mat=weight_rank_dist_opt(norm_st, deg=4);
	}else if (type=="man"){
		dist_mat=vegdist(norm_st, method="manhattan");
	}else if (type=="bray"){
		dist_mat=vegdist(norm_st, method="bray");
	}else if (type=="horn"){
		dist_mat=vegdist(norm_st, method="horn");
	}else if (type=="bin"){
		dist_mat=vegdist(norm_st, method="bin");
	}else if (type=="gow"){
		dist_mat=vegdist(norm_st, method="gower");
	}else if (type=="tyc"){
		dist_mat=thetaYC(norm_st);
	}else if (type=="minkp3"){
		dist_mat=dist(norm_st, method="minkowski", p=1/3);
	}else if (type=="minkp5"){
		dist_mat=dist(norm_st, method="minkowski", p=1/2);
	}

	dist_mat[dist_mat==0]=1e-323;

	return(dist_mat);
}

plot_text=function(strings){

        orig_par=par(no.readonly=T);

        par(family="Courier");
        par(oma=rep(.5,4));
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

        par(orig_par);

}


###############################################################################

output_fname_root = paste(OutputFileRoot, ".", DistType, sep="");

cat("\n");
cat("Loading summary table A:", InputSumTabA, "\n");
counts_mat_A=load_summary_table(InputSumTabA);
cat("Loading summary table B:", InputSumTabB, "\n");
counts_mat_B=load_summary_table(InputSumTabB);

# Reconcile summary table IDs through mapping file
samples_stA=rownames(counts_mat_A);
samples_stB=rownames(counts_mat_B);

cat("Loading Mapping file:", MappingFile, "\n");
map_info=load_mapping_file(MappingFile, samples_stA, samples_stB);

cat("Removing samples without complete mappings...\n");
counts_mat_A=counts_mat_A[map_info[["a_id"]],];
counts_mat_B=counts_mat_B[map_info[["b_id"]],];

num_samples=nrow(counts_mat_A);
cat("Num usable samples: ", num_samples, "\n");

###############################################################################

# Normalize counts
cat("Normalizing counts...\n");
norm_mat_A=normalize(counts_mat_A);
norm_mat_B=normalize(counts_mat_B);

###############################################################################

# Compute full distances
cat("Computing distances...\n");
dist_mat_A=compute_dist(norm_mat_A, DistType);
dist_mat_B=compute_dist(norm_mat_B, DistType);

###############################################################################

pdf(paste(OutputFileRoot, ".cmp_dist.pdf", sep=""), height=8.5, width=8);

param_summary=capture.output({
	cat("Input Summary Table A:", InputSumTabA, "\n");
	cat("Input Summary Table B:", InputSumTabB, "\n");
	cat("Mapping File         :", MappingFile, "\n");
	cat("Output File          :", OutputFileRoot, "\n");
	cat("Distance Type        :", DistType, "\n");
	cat("\n");
	
});
plot_text(param_summary);

###############################################################################

test=1;

###############################################################################

if(!test){
	cat("Bootstrapping Mantel Correlation...\n");
	mantel_res=mantel(dist_mat_A, dist_mat_B, permutations=10000);
	print(mantel_res);

	mantel_cor=mantel_res[["statistic"]];
	mantel_pval=mantel_res[["signif"]];
	cat("\n");
	cat("Correlation: ", mantel_cor, " ", "P-val: ", mantel_pval, "\n");
	cat("\n");

	plot_text(c(
		"Mantel Test based on Pearson's Product-Moment Correlation:",
		paste("Correlation:", mantel_cor, sep=""),
		paste("    P-value:", mantel_pval, sep=""),
		"",
		"Note: Correl Range is -1.0 to 1.0, and Null Hypothesis is 0.0 correlation."

	));
}

##############################################################################

find_extremes=function(pts){

	num_pts=nrow(pts);

	pts_sorted_by_x=sort(pts[,1]);
	pts_sorted_by_y=sort(pts[,2]);

	# Find distances from center
	centroid=apply(pts, 2, median);
	print(centroid);
	dc=dist_from_centr=apply(pts, 1, function(x){
		sqrt((x[1]-centroid[1])^2+(x[2]-centroid[2])^2)})
	dc_sort=sort(dc, decreasing=T);

	sample_ids=unique(c(
		names(pts_sorted_by_x[1]),
		names(pts_sorted_by_y[1]),
		names(pts_sorted_by_x[num_pts]),
		names(pts_sorted_by_y[num_pts]),
		names(dc_sort[1:4])
	));

	return(sample_ids);

}

expand_range=function(x, fact=.1){
	mn=min(x);
	mx=max(x);
	diff=(mx-mn);
	return(c(mn-fact*diff, mx+fact*diff));
	
}

compare_mds=function(apts, bpts, type, aclus, bclus, aname, bname){

	palette_col=c("red", "green", "blue", "cyan", "magenta", "orange", "gray", "pink", "black", "purple", "brown", "aquamarine");
	num_pref_col=length(palette_col);
	num_clus=length(unique(aclus));	

	if(num_clus>num_pref_col){
		palette_col=rainbow(n=num_clus, start=0, end=4/6);
	}


	num_samp=nrow(apts);
	
	aout=find_extremes(apts);
	bout=find_extremes(bpts);

	ax=1:num_samp;
	bx=1:num_samp;

	names(ax)=rownames(apts);
	names(bx)=rownames(bpts);

	ax=ax[aout];
	bx=bx[bout];

	bothx=unique(c(ax, bx));

	cat("Extremes/Outliers Labeled:\n");
	aoutnames=rownames(apts)[bothx];
	boutnames=rownames(bpts)[bothx];
	print(aoutnames);
	print(boutnames);

	par(mfrow=c(2,2));

	plot(apts, main=paste(type, ": ", aname, sep=""), xlab="Dim 1", ylab="Dim 2", col=aclus, xlim=expand_range(apts));
	text(apts[bothx,], aoutnames, cex=.3);
	mtext(paste("Colored by ", aname, sep=""));
	plot(bpts, main=paste(type, ": ", bname, sep=""), xlab="Dim 1", ylab="Dim 2", col=aclus, xlim=expand_range(bpts));
	text(bpts[bothx,], boutnames, cex=.3);

	plot(apts, main=paste(type, ": ", aname, sep=""), xlab="Dim 1", ylab="Dim 2", col=bclus, xlim=expand_range(apts));
	text(apts[bothx,], aoutnames, cex=.3);
	plot(bpts, main=paste(type, ": ", bname, sep=""), xlab="Dim 1", ylab="Dim 2", col=bclus, xlim=expand_range(bpts));
	text(bpts[bothx,], boutnames, cex=.3);
	mtext(paste("Colored by ", bname, sep=""));

}

compute_pseudof=function(clsmem, distmat){

	# Compute SS Between
	#centroid_distmat=compute_centroids(clsmem, distmat);

	# Compute SS Within
	num_grps=length(unique(clsmem));
	num_samples=length(clsmem);
	distmat2d=as.matrix(distmat);

	tsw=0;
	tsb=0;
	nsb=0;
	nsw=0;

	for(i in 1:num_grps){
		grp_ix=(clsmem==i);
		for(j in 1:num_grps){
			grp_jx=(clsmem==j);

			subdist=distmat2d[grp_ix, grp_jx];

			if(i==j){
				
				# cat("SSW:\n");
				# print(dim(subdist));
				ssd=sum(subdist^2)/2;

				rows=nrow(subdist);
				num_dist=rows*(rows-1)/2;	# Number of distances in half matrix	
				
				tsw=tsw+ssd;
				nsw=nsw+num_dist;
			}else{

				# cat("SSB:\n");
				# print(dim(subdist));
				ssd=sum(subdist^2);

				num_dist=nrow(subdist)*ncol(subdist);

				tsb=tsb+ssd;
				nsb=nsb+num_dist;
			}

		}
	}

	# Compute sum of SS's based on Mean Squared
	ssb=(tsb/nsb)*num_grps;
	ssw=(tsw/nsw)*num_samples;

	# Compute Variance by adjusting for degree of freedom
	b_var=ssb/(num_grps-1);
	w_var=ssw/(num_samples-num_grps);

	# Return pseudo F-stat
	pseudof=b_var/w_var;
	if(!length(pseudof)){
		pseudof=0;
	}
	return(pseudof);

}

compare_pseudof=function(dista, distb, grp_hcla, grp_hclb, max_k, namea, nameb){

	amsd_byA=numeric(max_k-1);
	bmsd_byA=numeric(max_k-1);
	amsd_byB=numeric(max_k-1);
	bmsd_byB=numeric(max_k-1);

	for(clix in 2:max_k){	
		cat("Cutting tree to k=", clix, "\n");
		mem_byA=cutree(grp_hcla, k=clix);
		mem_byB=cutree(grp_hclb, k=clix);
		
		cat("Computing SSD:\n");
		amsd_byA[clix-1]=compute_pseudof(mem_byA, dista);
		bmsd_byA[clix-1]=compute_pseudof(mem_byA, distb);
		amsd_byB[clix-1]=compute_pseudof(mem_byB, dista);
		bmsd_byB[clix-1]=compute_pseudof(mem_byB, distb);
	}

	max_asmd=max(amsd_byA, amsd_byB, na.rm=T);
	max_bsmd=max(bmsd_byA, bmsd_byB, na.rm=T);
	min_asmd=min(amsd_byA, amsd_byB, na.rm=T);
	min_bsmd=min(bmsd_byA, bmsd_byB, na.rm=T);

	asmd_range=c(min_asmd, max_asmd);
	bsmd_range=c(min_bsmd, max_bsmd);

	par(mfrow=c(2,3));


	# Clustering from A's perspective
	plot(2:max_k, amsd_byA, xlab="Num Clusters, k", ylab="Pseudo F-Stat", main=paste("Pseudo F-Stat: ", namea, sep=""), type="b", ylim=asmd_range);
	mtext(paste("Clustered by Optimal ", namea, " Groupings", sep=""), cex=.6);

	plot(2:max_k, amsd_byB, xlab="Num Clusters, k", ylab="Pseudo F-Stat", main=paste("Pseudo F-Stat: ", namea, sep=""), type="b", ylim=asmd_range);
	mtext(paste("Clustered by Optimal ", nameb, " Groupings", sep=""), cex=.6);

	lograt=log(amsd_byB/amsd_byA);
	lograt[!is.finite(lograt)]=0;
	lims=c(-1,1)*max(abs(lograt), rm.na=T);
	plot(2:max_k, lograt, xlab="Num Clusters, k", ylab=paste("Pseudo F-Stat LogRatio(", namea, ")", sep=""),  main=paste("Pseudo F-stat Ratio"), type="b", ylim=lims);
	abline(h=0, col="blue");
	mtext(paste(namea, ": By ", nameb, "/", namea, " Groupings", sep=""), cex=.6);


	# Clustering from B's perspective
	plot(2:max_k, bmsd_byB, xlab="Num Clusters, k", ylab="Pseudo F-Stat", main=paste("Pseudo F-stat: ", nameb, sep=""), type="b", ylim=bsmd_range);
	mtext(paste("Clustered by Optimal ", nameb, " Groupings", sep=""), cex=.6);

	plot(2:max_k, bmsd_byA, xlab="Num Clusters, k", ylab="Pseudo F-Stat", main=paste("Pseudo F-stat: ", nameb, sep=""), type="b", ylim=bsmd_range);
	mtext(paste("Clustered by Optimal ", namea, " Groupings", sep=""), cex=.6);

	lograt=log(bmsd_byA/bmsd_byB);
	lograt[!is.finite(lograt)]=0;
	lims=c(-1,1)*max(abs(lograt), rm.na=T);
	plot(2:max_k, lograt, xlab="Num Clusters, k", ylab=paste("Pseudo F-Stat LogRatio(", nameb, ")", sep=""),  main=paste("Pseudo F-stat Ratio"), type="b", ylim=lims);
	abline(h=0, col="blue");
	mtext(paste(nameb, ": By ", namea, "/", nameb, " Groupings", sep=""), cex=.6);


}

compare_dendrograms=function(hclA, hclB, num_cuts, namea, nameb, idsb){

	color_denfun_bySample=function(n){
		if(is.leaf(n)){
			leaf_attr=attributes(n);
			leaf_name=leaf_attr$label;
			ind_color=sample_to_color_map[leaf_name];
			if(is.null(ind_color)){
				ind_color="black";
			}

			attr(n, "nodePar") = c(leaf_attr$nodePar,
							list(lab.col=ind_color));
		}
		return(n);
	}

	text_scale_denfun=function(n){
		if(is.leaf(n)){
			leaf_attr=attributes(n);
			leaf_name=leaf_attr$label;
			attr(n, "nodePar") = c(leaf_attr$nodePar,
						cex=0,
						lab.cex=label_scale);
		}
		return(n);
	}

	orig_par=par(no.readonly=T);

	par(mar=c(10,2,3,.5));
	par(mfrow=c(2,1));

	dendra=as.dendrogram(hclA);
	dendrb=as.dendrogram(hclB);

	label_scale=.2;
	dendra=dendrapply(dendra, text_scale_denfun);
	dendrb=dendrapply(dendrb, text_scale_denfun);

	mem_byA=cutree(hclA, k=num_cuts);
	sample_to_color_map=mem_byA;
	dendra=dendrapply(dendra, color_denfun_bySample);
	names(sample_to_color_map)=idsb;
	dendrb=dendrapply(dendrb, color_denfun_bySample);
	

	plot(dendra, main=paste("Cut by ", namea, "'s clustering", sep=""));
	plot(dendrb, main=nameb);

	# Plot shared statistics
	
	shared_mat=matrix(0, nrow=num_cuts, ncol=num_cuts);
	samples_a=names(mem_byA);

	mem_byB=cutree(hclB, k=num_cuts);
	names(mem_byB)=names(mem_byA);

	num_samples=length(mem_byA);
	cat("Num Samples: ", num_samples, "\n", sep="");

	for(r in 1:num_cuts){

		samples_in_r=samples_a[(mem_byA==r)];

		for(c in 1:num_cuts){
		
			total=sum(mem_byB==c);
			samples_in_c=(mem_byB[samples_in_r]==c);
			overlapping=sum(mem_byB[samples_in_r]==c);

			shared_mat[r, c]=overlapping/num_samples;
		}
	}
	
	print(shared_mat);

	par(orig_par);



}

##############################################################################

classic_mds_pts_A=matrix(0, nrow=num_samples, ncol=2); 
nonparm_mds_pts_A=matrix(0, nrow=num_samples, ncol=2); 
classic_mds_pts_B=matrix(0, nrow=num_samples, ncol=2); 
nonparm_mds_pts_B=matrix(0, nrow=num_samples, ncol=2); 

class_mdsA_res=cmdscale(dist_mat_A, k=2);
class_mdsB_res=cmdscale(dist_mat_B, k=2);
classic_mds_pts_A=class_mdsA_res;
classic_mds_pts_B=class_mdsB_res;

nonpr_mdsA_res=isoMDS(dist_mat_A, k=2);
nonpr_mdsB_res=isoMDS(dist_mat_B, k=2);
nonparm_mds_pts_A=nonpr_mdsA_res$points;
nonparm_mds_pts_B=nonpr_mdsB_res$points;

hcl_A=hclust(dist_mat_A, method="ward.D");
hcl_B=hclust(dist_mat_B, method="ward.D");

cuts=log2(num_samples);
clus4_A=cutree(hcl_A, k=cuts);
clus4_B=cutree(hcl_B, k=cuts);

cat("Comparing MDS plots:\n");
par(mfrow=c(2,2));
compare_mds(classic_mds_pts_A, classic_mds_pts_B, "Classical MDS", clus4_A, clus4_B, map_info[["a"]], map_info[["b"]]);
compare_mds(nonparm_mds_pts_A, nonparm_mds_pts_B, "NonMetric MDS", clus4_A, clus4_B, map_info[["a"]], map_info[["b"]]);

##############################################################################

for(cix in 2:cuts){
	compare_dendrograms(hcl_A, hcl_B, cix, map_info[["a"]], map_info[["b"]], map_info[["b_id"]]);
	compare_dendrograms(hcl_B, hcl_A, cix, map_info[["b"]], map_info[["a"]], map_info[["a_id"]]);
}

##############################################################################

cat("Comparing cluster separation:\n");
compare_pseudof(dist_mat_A, dist_mat_B, hcl_A, hcl_B,  max_k=22, map_info[["a"]], map_info[["b"]]);


##############################################################################

cat("Comparing distance distributions:\n");

par(mfrow=c(2,2));

hist(dist_mat_A, xlab="Distances", main=map_info[["a"]]);
hist(dist_mat_B, xlab="Distances", main=map_info[["b"]]);

if(!test){
	cat("Computing 2D histogram/Heatmap...\n");
	k=kde2d(dist_mat_A, dist_mat_B, n=500);
	image(k, col=rev(rainbow(100, start=0, end=4/6)), xlab=map_info[["a"]], ylab= map_info[["b"]], main=sprintf("Correlation: %3.3f", cor(dist_mat_A, dist_mat_B)));
}

max_dist_A=max(dist_mat_A);
max_dist_B=max(dist_mat_B);

plot(dist_mat_A, dist_mat_B, main="All Distances", xlab=map_info[["a"]], ylab= map_info[["b"]], cex=.5, xlim=c(0, max_dist_A), ylim=c(0, max_dist_B));

# Subsample so we can differentiate all the points in the scatter plot
num_dist=length(dist_mat_A);

##############################################################################

cat("Analyze sub-cluster statistics\n");

analyze_subclusters=function(hclA, hclB, distmatA, distmatB, num_cuts, namea, nameb, idsb){

	# Mean sum of squared distances 
	msd=function(dist){
		# Square matrix
		num_samp=ncol(dist);
		num_dist=(num_samp*(num_samp-1));
		#cat("Num Dist: ", num_dist, "\n");
		msd=sum(dist^2)/num_dist;
		return(msd);
	}

	# Spearman correlation
	distcorel=function(dista, distb){
		return(cor(dista, distb, method="spearman"));	
	}

	dist2da=as.matrix(distmatA);
	dist2db=as.matrix(distmatB);

	msd_mat_a=matrix(NA, nrow=num_cuts, ncol=num_cuts);
	msd_mat_b=matrix(NA, nrow=num_cuts, ncol=num_cuts);
	cor_mat=matrix(NA, nrow=num_cuts, ncol=num_cuts);

	par(mfrow=c(3,3));

	for(clx in 1:num_cuts){
		cat("Analyzing ", clx, " cuts to: ", namea, "\n");
		memA=cutree(hclA, k=clx);
		
		#memB=memA;
		#names(memB)=idsb;

		for(clid in 1:clx){
			cat("	Cluster ", clid, " of ", clx, "\n");
			memids=(memA==clid);

			cl_dista=dist2da[memids, memids];
			cl_distb=dist2db[memids, memids];
			
			arange=range(cl_dista);
			
			msdA=msd(cl_dista);
			msdB=msd(cl_distb);

			dist_arr_a=as.dist(cl_dista);
			dist_arr_b=as.dist(cl_distb);
			cor=distcorel(dist_arr_a, dist_arr_b);

			plot(dist_arr_a, dist_arr_b, main=paste(clid, "/", clx, ": distances"),  xlab=namea, ylab=nameb, cex=.5);
		
			cat("  MSD A: ", msdA, ", Range: ", arange[1], "-", arange[2], " MSD B: ", msdB, "    Cor: ", cor, "\n");

			msd_mat_a[clx, clid]=msdA;
			msd_mat_b[clx, clid]=msdB;
			cor_mat[clx, clid]=cor;
		}

	}

	par(mfrow=c(3,1));
	maxmsd=max(msd_mat_a, na.rm=T);
	plot(0,0, type="n", xlim=c(1, num_cuts), ylim=c(0, maxmsd), xlab="Cluster Cuts", ylab="MSD", main=paste(namea, " clustered by ", namea, sep=""));
	abline(h=msd_mat_a[1,1], col="blue", lty=2);
	for(clx in 1:num_cuts){
		points(rep(clx, clx), msd_mat_a[clx, 1:clx], col=1:clx);	
	}

	maxmsd=max(msd_mat_b, na.rm=T);
	plot(0,0, type="n", xlim=c(1, num_cuts), ylim=c(0, maxmsd), xlab="Cluster Cuts", ylab="MSD", main=paste(nameb, " clustered by ", namea, sep=""));
	abline(h=msd_mat_b[1,1], col="blue", lty=2);
	for(clx in 1:num_cuts){
		points(rep(clx, clx), msd_mat_b[clx, 1:clx], col=1:clx);	
	}

	cor_range=c(-1,1)*max(abs(cor_mat), na.rm=T);
	plot(0,0, type="n", xlim=c(1, num_cuts), ylim=cor_range, xlab="Cluster Cuts", ylab="Distance Correlation", main=paste(nameb, " clustered by ", namea, sep=""));
	abline(h=cor_mat[1,1], col="blue", lty=2);
	abline(h=0, col="grey");
	for(clx in 1:num_cuts){
		points(rep(clx, clx), cor_mat[clx, 1:clx], col=1:clx);	
	}

}


analyze_subclusters(hcl_A, hcl_B, dist_mat_A, dist_mat_B, cuts, map_info[["a"]],  map_info[["b"]], map_info[["b_id"]]);
analyze_subclusters(hcl_B, hcl_A, dist_mat_B, dist_mat_A, cuts, map_info[["b"]],  map_info[["a"]], map_info[["a_id"]]);


##############################################################################

cat("\nDone.\n")
dev.off();
warn=warnings();
if(length(warn)){
        print(warn);
}
q(status=0);
