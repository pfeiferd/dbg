package org.metagene.genestrip.finertree.cluster;

// This follows the simple standard algorithm "HAC" for agglomerative clustering
// as described in Figure 17.2. in Manning's "Introduction to Information Retrieval"
// Too inefficient for larger problems, but sufficient here.
public class SimpleAggloClustering {
    public enum Method { SINGLE_LINKAGE, COMPLETE_LINKAGE, GROUP_AVERAGE, WHEIGHTED_GROUP_AVERAGE };

    private final Method method;

    public SimpleAggloClustering(Method method) {
        this.method = method;
    }

    public DendrogramNode cluster(Similarity similarity) {
        DendrogramNode[] clusters = new DendrogramNode[similarity.values()];
        // Only about half of this array is really needed. (Could optimize, but it's not worth it.)
        double[][] sims = new double[clusters.length][clusters.length];
        int[] sizes = new int[clusters.length];

        for (int i = 0; i < clusters.length; i++) {
            clusters[i] = new DendrogramNode(i, similarity.getSimilarity(i, i));
            sizes[i] = 1;
        }
        for (int i = 0; i < sims.length; i++) {
            for (int j = i + 1; j < sims.length; j++) {
                sims[j][i] = sims[i][j] = similarity.getSimilarity(i, j);
            }
        }

        double bestSim;
        int bestI = -1;
        int bestJ;
        for (int k = 0; k < clusters.length - 1; k++) {
            bestSim = 0;
            bestI = 0;
            bestJ = 0;
            for (int i = 0; i < clusters.length; i++) {
                for (int j = i + 1; j < clusters.length; j++) {
                    if (clusters[i] != null && clusters[j] != null) {
                        if (sims[i][j] > bestSim) {
                            bestSim = sims[i][j];
                            bestI = i;
                            bestJ = j;
                        }
                    }
                }
            }
            DendrogramNode node = new DendrogramNode(clusters[bestI], clusters[bestJ], bestSim);
            clusters[bestI] = node;
            clusters[bestJ] = null;
            sizes[bestI] += sizes[bestJ];
            for (int h = 0; h < clusters.length; h++) {
                if (clusters[h] != null && h != bestI) {
                    sims[bestI][h] = sims[h][bestI] = similarity(similarity, sims, bestI, bestJ, h,sizes);
                }
            }
        }
        return clusters[bestI];
    }

    protected double similarity(Similarity similarity, double[][] sims, int bestI, int bestJ, int h, int[] sizes) {
        switch (method) {
            case SINGLE_LINKAGE:
                return singleLinkage(sims, bestI, bestJ, h, sizes);
            case COMPLETE_LINKAGE:
                return completeLinkage(sims, bestI, bestJ, h, sizes);
            case GROUP_AVERAGE:
                return groupAverage(sims, bestI, bestJ, h, sizes);
            default:
                return weightedGroupAverage(sims, bestI, bestJ, h, sizes);
        }
    }

    protected double singleLinkage(double[][] sims, int bestI, int bestJ, int h, int[] sizes) {
        return Math.max(sims[h][bestI], sims[h][bestJ]);
    }

    protected double completeLinkage(double[][] sims, int bestI, int bestJ, int h, int[] sizes) {
        return Math.min(sims[h][bestI], sims[h][bestJ]);
    }

    // According to:
    // https://en.wikipedia.org/wiki/UPGMA
    protected double groupAverage(double[][] sims, int bestI, int bestJ, int h, int[] sizes) {
        return (sizes[bestI] * sims[h][bestI] + sizes[bestJ] * sims[h][bestJ]) / (sizes[bestI] + sizes[bestJ]);
    }

    protected double weightedGroupAverage(double[][] sims, int bestI, int bestJ, int h, int[] sizes) {
        return (sims[h][bestI] + sims[h][bestJ]) / 2;
    }
}
