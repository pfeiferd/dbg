package org.metagene.genestrip.finertree.cluster;

import java.util.*;

// Too inefficient for larger problems, but sufficient here.
public class SimpleAggloClustering {
    public interface Similarity {
        public int values();
        public double getSimilarity(int i, int j);
    }

    // This follows the simple standard algorithm "HAC" for agglomerative clustering
    // as described in Figure 17.2. in Manning's "Introduction to Information Retrieval"
    public DendroGramNode cluster(Similarity similarity) {
        DendroGramNode[] clusters = new DendroGramNode[similarity.values()];
        // Only about half of this array is needed. (Could optimize, but it's not worth it.)
        double[][] sims = new double[clusters.length][clusters.length];

        for (int i = 0; i < clusters.length; i++) {
            clusters[i] = new DendroGramNode(i, similarity.getSimilarity(i, i));
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
            DendroGramNode node = new DendroGramNode(clusters[bestI], clusters[bestJ], bestSim);
            clusters[bestI] = node;
            clusters[bestJ] = null;
            for (int h = 0; h < clusters.length; h++) {
                if (h != bestJ && h != bestI) {
                    sims[bestI][h] = sims[h][bestI] = similarity(sims, bestI, bestJ, h);
                }
            }
        }
        return clusters[bestI];
    }

    // Single link with regard to similarity
    protected double similarity(double[][] sims, int bestI, int bestJ, int h) {
        return Math.max(sims[h][bestI], sims[h][bestJ]);
    }
}
