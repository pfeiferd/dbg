package org.metagene.genestrip.finertree.cluster;

public interface Similarity {
    public int values();
    public double getSimilarity(int i, int j);
}
