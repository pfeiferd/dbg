package org.metagene.genestrip.finertree;

import org.metagene.genestrip.make.GoalKey;

public enum FTGoalKey implements GoalKey {
    DENDROGRAM("dendrogram"),
    DENDRO_LATEX("dendrolatex", true),
    KMER_INDEX_BLOOM("kmerindexbloom"),
    INTERSECT_COUNT("intersectcount"),
    INTERSECT_CSV("intersectcsv", true),
    LOAD_KMER_INDEX("loadkmerindex"),
    STORE_KMER_INDEX("storekmerindex"),;

    private final boolean forUser;
    private final String name;

    private FTGoalKey(String name) {
        this(name, false);
    }

    private FTGoalKey(String name, boolean forUser) {
        this.name = name;
        this.forUser = forUser;
    }

    public boolean isForUser() {
        return forUser;
    }

    public String getName() {
        return name;
    }
}
