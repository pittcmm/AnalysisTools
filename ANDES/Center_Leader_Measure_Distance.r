#!/usr/bin/env Rscript

###############################################################################
#                                                                             # 
#       Copyright (c) 2009 J. Craig Venter Institute.                         #     
#       All rights reserved.                                                  #
#                                                                             #
###############################################################################
#                                                                             #
#    This program is free software: you can redistribute it and/or modify     #
#    it under the terms of the GNU General Public License as published by     #
#    the Free Software Foundation, either version 3 of the License, or        #
#    (at your option) any later version.                                      #
#                                                                             #
#    This program is distributed in the hope that it will be useful,          #
#    but WITHOUT ANY WARRANTY; without even the implied warranty of           #
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            #
#    GNU General Public License for more details.                             #
#                                                                             #
#    You should have received a copy of the GNU General Public License        #
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.    #
#                                                                             #
###############################################################################

###############################################################################

library('getopt');
library(MASS);
require(plotrix)
LEADER_COLOR="darkgreen";

params=c(
	"distance_matrix", "m", 1, "character",
	"distance_cutoff", "c", 1, "numeric",
	"leader_name", "l", 1, "character",
	"compare_list", "d", 2, "character",
	"output_root", "o", 2, "character",
	"num_steps", "s", 2, "numeric"
);

opt=getopt(spec=matrix(params, ncol=4, byrow=TRUE), debug=FALSE);
script_name=unlist(strsplit(commandArgs(FALSE)[4],"=")[1])[2];

usage = paste (
	"\nUsage:\n    ", script_name, "\n",
	"	-m <input distance matrix>\n",
	"	-c <distance cutoff>\n",
	"	-l <leader sample name>\n",
	"	[-s <number of steps]\n",
	"	[-o <output filename root>]\n",
	"\n",
	"Reads in distance matrix and based on the leader sample name\n",
	"splits the samples in the distance matrix into two or more groups.\n",
	"\n",
	"The -s option lets you set how many IN clusters to generate.\n",
	"The -c parameter lets you set exactly which sequences should be OUT.\n",
	"\n");

if(!length(opt$distance_matrix) || !length(opt$distance_cutoff) || !length(opt$leader_name)){
	cat(usage);
	q(status=-1);
}

InputDistanceMatrix=opt$distance_matrix;
DistanceCutoff=opt$distance_cutoff;
LeaderName=opt$leader_name;

if(length(opt$output_root)){
	OutputFileNameRoot=opt$output_root;
}else{
	OutputFileNameRoot=gsub("\\.r_distmat$", "", InputDistanceMatrix);
	OutputFileNameRoot=gsub("\\.distmat$", "", OutputFileNameRoot);
	OutputFileNameRoot=gsub("\\.dist_mat$", "", OutputFileNameRoot);
}

NumSteps=1;
if(length(opt$num_steps)){
	NumSteps=opt$num_steps;
}
dlist=0;
if(length(opt$compare_list)){
	dlist=opt$compare_list;
}


###############################################################################

cat("Input Distance Matrix: ", InputDistanceMatrix, "\n");
cat("Input Distance Cutoff: ", DistanceCutoff, "\n");
cat("Leader Name: ", LeaderName, "\n");
cat("Output Filename Root:", OutputFileNameRoot, "\n");
cat("Number of Steps from Leader: ", NumSteps, "\n");

###############################################################################

color_denfun_byIndividual=function(n, sample_to_color_map){

        if(is.leaf(n)){
                leaf_attr=attributes(n);
                leaf_name=leaf_attr$label;
                ind_color=sample_to_color_map[[leaf_name]];
                if(is.null(ind_color)){
                        ind_color="grey50";
                }

                attr(n, "nodePar") = c(leaf_attr$nodePar,
                                                list(lab.col=ind_color));
        }
        return(n);
}

text_scale_denfun=function(n, label_scale){
        if(is.leaf(n)){
                leaf_attr=attributes(n);
                leaf_name=leaf_attr$label;
                #attr(n, "nodePar") = c(leaf_attr$nodePar,
                #                       cex=0,
                #                       lab.cex=label_scale);
                att=attr(n, "nodePar");
                att$lab.cex=label_scale;
                att$cex=0;
                attr(n, "nodePar")=att;
        }
        return(n);
}

mark_sample_name_denfun=function(n, sample_list){
        if(is.leaf(n)){
                leaf_attr=attributes(n);
                leaf_name=leaf_attr$label;
				
				#cat(leaf_name, "\n");
				
                if(any(leaf_name==sample_list)){
					#cat(leaf_name, "\n");
                        att=attr(n, "nodePar");
                        att$cex=1;
                        att$pch=18;
                        att$col="red";
                        att$lab.col=LEADER_COLOR;
						att$lab.font=2;
                        attr(n, "nodePar")=att;
                }
        }
        return(n);
}

cluster_to_colormap=function(cluster){
	num_members=length(cluster);
	sample_names=names(cluster);
	map=list();
	
	#cat(sample_names, num_members, "\n");
	for(i in 1:num_members){
		#dim(cluster[i]);
		if (cluster[i]==0) {
			map[[sample_names[i]]]=1;
		} else {
			map[[sample_names[i]]]=cluster[i];
		}
	}	
	return(map);
}

###############################################################################

cluster_from_leader=function(distmat, leader_pos, dist_cutoff, num_steps){

	num_samples=nrow(distmat);
	num_clusters=num_steps+1;
	boundaries=seq(0,dist_cutoff, length.out=num_clusters);
	cat("Boundaries: \n");
	print(boundaries)
	leader_distances=distmat[leader_pos,];

	clusters=numeric(num_samples);
	for(cl_id in 1:num_clusters){
		lt=boundaries[cl_id]<=leader_distances;
		clusters[lt]=cl_id;
	}	

	#print(cbind(leader_distances,clusters))
	# Create clusters
	names(clusters)=sample_names;

	return(clusters);
}

cluster_from_leader2=function(distmat, leader_pos, dist_cutoff, num_steps){
	
	num_samples=nrow(distmat);
	num_clusters=num_steps+1;
	boundaries=seq(0,dist_cutoff, length.out=num_clusters);
	cat("Boundaries: \n");
	print(boundaries)
	leader_distances=distmat[leader_pos,];
	
	c2=numeric(num_samples);
	for(cl_id in 1:num_clusters){
		lt=boundaries[cl_id]<=leader_distances;
		c2[lt]=cl_id;
	}	
	
	#print(cbind(leader_distances,clusters))
	# Create clusters
	names(c2)=sample_names2;
	
	return(c2);
}
###############################################################################

# Load data
cat("Loading matrix.\n");
distmat=as.matrix(read.table(InputDistanceMatrix, header=TRUE, check.names=FALSE));
numSamples=nrow(distmat);
sample_names=colnames(distmat);
#cat(sample_names, "\n");
#dim(distmat);

if (length(dlist)>0) {
	d_samples = as.matrix(read.table(dlist, header=FALSE, check.names=FALSE));
}

# Compute who's in or out
leader_pos=which(sample_names==LeaderName);
if(length(leader_pos)==0){
	cat("Could not find your leader in the distance matrix\n");
	cat("Leader: '", LeaderName, "'\n", sep="");
	quit(status=-1);
}
#cat(leader_pos, sample_names[leader_pos]);
#exit;
clusters=cluster_from_leader(distmat, leader_pos, DistanceCutoff, NumSteps);
clusters[clusters==0]=1;
out_clusters=NumSteps+1;
in_clusters=1:NumSteps;
#print(clusters);

boundaries=seq(0, DistanceCutoff, length.out=out_clusters);
cl_names=sprintf("In <= %2.1f",boundaries[-1]);
cl_names[out_clusters]=sprintf("Out > %2.1f", DistanceCutoff);

# remove non zero non diagonals
for(i in 1:numSamples){
	for(j in 1:numSamples){
		if(distmat[i,j]<=0 && i!=j){
			distmat[i,j]=1e-323;
		}
	}
}
		
# Compute Clusters
meth=c("ward","complete","single");
meth_name=c("Ward's Minimum Variance","Complete Linkage","Single Linkage");
hclust_list=list();
dist=as.dist(distmat);
for(i in 1:length(meth)){
	hclust_list[[i]]=hclust(dist, method=meth[i]);
}

# Generate MDS
mds=isoMDS(distmat);
d_pos=vector();
for(i in 1:length(d_samples)){
	d_pos[i]=which(sample_names==d_samples[i]);
}


mds_red=isoMDS(distmat[-c(d_pos),-c(d_pos)]);


################################################################################

plot_legend=function(names, col){
	def_mar=par()$mar;
	new_mar=def_mar;
	new_mar[2]=0;
	new_mar[4]=0;
	par(mar=c(new_mar));
	plot(0,0, xlim=c(-10,100), ylim=c(-100, 0), ylab="", xlab="", type="n", xaxt="n", yaxt="n", bty="n");
	legend(x=0, y=0, legend=names, fill=col, cex=1.5);
	print(col);
	par(mar=def_mar);
}

################################################################################

pdf(paste(OutputFileNameRoot, ".wLeader.pdf", sep=""), height=8.5, width=11); 

layout_mat=matrix(c(1,1,1,1,1,2,
	 1,1,1,1,1,2), nrow=2, ncol=6, byrow=TRUE);
layout(layout_mat);

text_scale=60/numSamples;
color_map=cluster_to_colormap(clusters);
#print(color_map);
leader_list=c(LeaderName);
palette(c(rainbow(NumSteps, start=2/6, end=1), "black", "red"));

#par(mar=c(7.1, 4.1,4.1,0));
# Plot each hclust type
#for(i in 1:length(meth)){
	#cat(meth, "\n");
	#print(color_map);
#	dend=as.dendrogram(hclust_list[[i]]);
#	dend=dendrapply(dend, color_denfun_byIndividual, color_map);
#	dend=dendrapply(dend, text_scale_denfun, text_scale);
#	dend=dendrapply(dend, mark_sample_name_denfun, leader_list);
#	plot(dend, main=OutputFileNameRoot);
#	mtext(meth_name[i], line=0);
#	plot_legend(cl_names, 1:out_clusters);
#}


par(mar=c(5.1, 4.1,4.1,0));

# Plot MDS without names

csize=1.75

plot(mds$points[,1], mds$points[,2], xlab="", ylab="", type="n");
shapes=rep(16, numSamples);
shapes[clusters==out_clusters]=17;

points(mds$points[,1], mds$points[,2], cex=2, col=clusters, pch=shapes);
#draw.circle(mds$points[leader_pos,1], mds$points[leader_pos,2], radius=DistanceCutoff);
cluster_sizes=table(clusters);
#print(cluster_sizes);
cl_points=mds$points[clusters==1,];
if(cluster_sizes[1]>1){
	hull_points=chull(cl_points);
	hull_points=c(hull_points, hull_points[1]);
	lines(cl_points[hull_points,1], cl_points[hull_points,2], col="blue", pch=2, lwd=2, lty=3);
}else{
	points(cl_points[1], cl_points[2], cex=3, col="blue");
}
for(i in 1:length(d_samples)){
	segments(mds$points[leader_pos,1], mds$points[leader_pos,2], x1 = mds$points[d_samples[i],1], y1 = mds$points[d_samples[i],2]);
	points(mds$points[d_samples[i],1], mds$points[d_samples[i],2], col='red', pch=19, cex=2);
	text(mds$points[d_samples[i],1], mds$points[d_samples[i],2], labels=paste(distmat[d_samples[i],LeaderName], d_samples[i]), pos=4, cex=csize)
	print(d_samples[i]);
}
points(mds$points[leader_pos,1], mds$points[leader_pos,2], cex=3, pch=16, col=LEADER_COLOR);
text(mds$points[leader_pos,1], mds$points[leader_pos,2], labels=LeaderName, col=LEADER_COLOR, pos=2, cex=csize);
plot_legend(c(cl_names,"Viruses of\nInterest"), 1:(out_clusters+1));	

# Plot MDS labels
numSamples2=nrow(distmat[-c(d_pos),-c(d_pos)]);
sample_names2=colnames(distmat[-c(d_pos),-c(d_pos)])
c2=cluster_from_leader2(distmat[-c(d_pos),-c(d_pos)], leader_pos, DistanceCutoff, NumSteps);
c2[c2==0]=1;
out_c2=NumSteps+1;
in_c2=1:NumSteps;

plot(mds_red$points[,1], mds_red$points[,2], xlab="", ylab="", type="n");
shapes=rep(1, numSamples2);
shapes[c2==out_c2]=17;
points(mds_red$points[leader_pos,1], mds_red$points[leader_pos,2], cex=3, pch=16, col=LEADER_COLOR);
text(mds_red$points[leader_pos,1], mds_red$points[leader_pos,2], labels=LeaderName, col=LEADER_COLOR, pos=4, cex=csize);
points(mds_red$points[,1], mds_red$points[,2], col=c2, pch=shapes, cex=2);
cluster_sizes=table(c2);
cl_points=mds_red$points[c2==1,];
if(cluster_sizes[1]>1){
	hull_points=chull(cl_points);
	hull_points=c(hull_points, hull_points[1]);
	lines(cl_points[hull_points,1], cl_points[hull_points,2], col="blue", pch=2, lwd=.5, lty=3);
}else{
	points(cl_points[1], cl_points[2], cex=2, col="blue");
}
#oname=c("A/CALIFORNIA/7/2009");
#points(mds_red$points[oname,1], mds_red$points[oname,2], col=c2, pch=15, cex=3);
#text(mds_red$points[oname,1], mds_red$points[oname,2], labels=oname, pos=4, cex=csize)
plot_legend(cl_names, 1:out_c2);

#plot(mds$points[,1], mds$points[,2], xlab="", ylab="", type="n");
#points(mds$points[leader_pos,1], mds$points[leader_pos,2], cex=2.5, pch=16, col=LEADER_COLOR);
#text(mds$points[,1], mds$points[,2], col=clusters, labels=sample_names, cex=text_scale, adj=0);
#plot_legend(cl_names, 1:out_clusters);

dev.off();

################################################################################
# Output clusters

num_clusters=max(clusters);
for(cl in 1:num_clusters){
	outputfilename=paste(OutputFileNameRoot, ".", cl_names[cl], sep="");
	fc=file(outputfilename, "w");
	members=names(clusters[clusters==cl]);
	write(members,file=fc);
	close(fc);
}

#------------------------------------------------------------------------------
# Output counts

fc=file(paste(OutputFileNameRoot, ".counts", sep=""), "w");
for(cl in 1:num_clusters){
	len=length(clusters[clusters==cl]);
	cat(file=fc, sprintf("%s\t%i\n", cl_names[cl], len), sep="");	
}
close(fc);

#------------------------------------------------------------------------------
# Output cluster members and sample ids

fc=file(paste(OutputFileNameRoot, ".groups", sep=""), "w");
for(cl in 1:num_clusters){
	members=names(clusters[clusters==cl]);
	num_members=length(members);
	for(m in 1:num_members){
		cat(file=fc, cl_names[cl] , "\t", members[m], "\n", sep="");
	}
}
close(fc);


################################################################################

cat("done.\n\n");
