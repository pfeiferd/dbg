/*
 * 
 * “Commons Clause” License Condition v1.0
 * 
 * The Software is provided to you by the Licensor under the License, 
 * as defined below, subject to the following condition.
 * 
 * Without limiting other conditions in the License, the grant of rights under the License 
 * will not include, and the License does not grant to you, the right to Sell the Software.
 * 
 * For purposes of the foregoing, “Sell” means practicing any or all of the rights granted 
 * to you under the License to provide to third parties, for a fee or other consideration 
 * (including without limitation fees for hosting or consulting/ support services related to 
 * the Software), a product or service whose value derives, entirely or substantially, from the 
 * functionality of the Software. Any license notice or attribution required by the License 
 * must also include this Commons Clause License Condition notice.
 * 
 * Software: genestrip-ft
 * 
 * License: Apache 2.0
 * 
 * Licensor: Daniel Pfeifer (daniel.pfeifer@progotec.de)
 * 
 */
package org.metagene.genestrip.finertree.goals;

import it.unimi.dsi.fastutil.objects.Object2LongMap;
import me.tongfei.progressbar.ProgressBar;
import org.metagene.genestrip.GSConfigKey;
import org.metagene.genestrip.GSProject;
import org.metagene.genestrip.finertree.FTConfigKey;
import org.metagene.genestrip.finertree.FTGoalKey;
import org.metagene.genestrip.finertree.FinerTreeMaker;
import org.metagene.genestrip.finertree.bloom.XORKMerIndexBloomFilter;
import org.metagene.genestrip.make.Goal;
import org.metagene.genestrip.make.GoalKey;
import org.metagene.genestrip.make.ObjectGoal;
import org.metagene.genestrip.store.Database;
import org.metagene.genestrip.store.KMerSortedArray;
import org.metagene.genestrip.tax.Rank;
import org.metagene.genestrip.tax.SmallTaxTree;
import org.metagene.genestrip.util.progressbar.GSProgressBarCreator;
import org.metagene.genestrip.util.progressbar.GSProgressUpdate;

import java.io.File;
import java.util.*;

public class KMerIntersectCountGoal extends ObjectGoal<KMerIntersectCountGoal.IntersectionsPerNode, GSProject> {
    public interface IntersectionsPerNode  {
        public Set<SmallTaxTree.SmallTaxIdNode> getParentNodes();
        public long getIntersectionCount(SmallTaxTree.SmallTaxIdNode parent, int child1, int child2);
        public long getKMerSpreadSum(SmallTaxTree.SmallTaxIdNode parent);
        public long getKMerSum(SmallTaxTree.SmallTaxIdNode parent);
        public double getJaccardIndex(SmallTaxTree.SmallTaxIdNode parent, int i, int j, boolean withChildCounts);
        public double getAvgKMerSpread(SmallTaxTree.SmallTaxIdNode parent);
        public double getOverspreadRatio(SmallTaxTree.SmallTaxIdNode parent);
        public long getSubnodesKMerCount(SmallTaxTree.SmallTaxIdNode parent);
    }

    private static int INITIAL_MAX_CHILDREN = 256;

    public static GoalKey GOAL_KEY = new GoalKey() {
        @Override
        public String getName() {
            return "intersectcount";
        }
    };

    private final ObjectGoal<Database, GSProject> storeGoal;
    private final ObjectGoal<XORKMerIndexBloomFilter, GSProject> bloomFilterGoal;

    @SafeVarargs
    public KMerIntersectCountGoal(GSProject project, ObjectGoal<Database, GSProject> storeGoal,
                              ObjectGoal<XORKMerIndexBloomFilter, GSProject> bloomFilterGoal,
                              Goal<GSProject>... deps) {
        super(project, FTGoalKey.INTERSECT_COUNT, Goal.append(deps, storeGoal, bloomFilterGoal));
        this.storeGoal = storeGoal;
        this.bloomFilterGoal = bloomFilterGoal;
    }

    @Override
    protected void doMakeThis() {
        boolean [] ranksToRefine = new boolean[Rank.values().length];
        Collection<Rank> toRefine = (Collection<Rank>) configValue(FTConfigKey.REFINEMENT_RANKS);
        for (Rank r : toRefine) {
            ranksToRefine[r.ordinal()] = true;
        }
        KMerSortedArray<SmallTaxTree.SmallTaxIdNode> kMerSortedArray = storeGoal.get().convertKMerStore();
        XORKMerIndexBloomFilter bloomFilter = bloomFilterGoal.get();

        IntersectionsPerNodeImpl intersectionsPerNode = new IntersectionsPerNodeImpl();

        long max = kMerSortedArray.getEntries();
        long[] current = new long[1];
        GSProgressUpdate update = new GSProgressUpdate() {
            @Override
            public long current() {
                return current[0];
            }

            @Override
            public long max() {
                return max;
            }
        };
        try (ProgressBar pb = createProgressBar(update)) {
            kMerSortedArray.visit(new KMerSortedArray.KMerSortedArrayVisitor<SmallTaxTree.SmallTaxIdNode>() {
                private boolean[] bits = new boolean[INITIAL_MAX_CHILDREN];

                @Override
                public void nextValue(KMerSortedArray<SmallTaxTree.SmallTaxIdNode> trie, long kmer, short index, long pos) {
                    current[0] = pos;
                    SmallTaxTree.SmallTaxIdNode parent = kMerSortedArray.getValueForIndex(index);
                    if (parent != null) {
                        if (ranksToRefine[parent.getRankOrdinal()]) {
                            SmallTaxTree.SmallTaxIdNode[] children = parent.getSubNodes();
                            if (children != null && children.length > 0) {
                                int n;
                                for (n = bits.length; n < children.length; n *= 2) {
                                }
                                if (n > bits.length) {
                                    bits = new boolean[n];
                                }
                                int spread = 0;
                                for (int i = 0; i < children.length; i++) {
                                    bits[i] = checkSubtree(children[i], kmer);
                                    if (bits[i]) {
                                        spread++;
                                    }
                                }
                                bits[children.length] = bloomFilter.containsLongShort(kmer, KMerIndexBloomGoal.OTHER_VALUE);
                                if (bits[children.length]) {
                                    spread++;
                                }
                                intersectionsPerNode.incKMerSpread(parent, spread);
                                for (int i = 0; i <= children.length; i++) {
                                    for (int j = i; j <= children.length; j++) {
                                        if (bits[i] && bits[j]) {
                                            intersectionsPerNode.incIntersectionCount(parent, i, j);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                protected boolean checkSubtree(SmallTaxTree.SmallTaxIdNode node, long kmer) {
                    if (bloomFilter.containsLongShort(kmer, node.storeIndex)) {
                        return true;
                    }
                    if (node.getSubNodes() != null) {
                        SmallTaxTree.SmallTaxIdNode[] children = node.getSubNodes();
                        for (int i = 0; i < children.length; i++) {
                            if (checkSubtree(children[i], kmer)) {
                                return true;
                            }
                        }
                    }
                    return false;
                }
            });
        }

        Object2LongMap<SmallTaxTree.SmallTaxIdNode> stats = kMerSortedArray.getNKmersPerTaxid();
        stats.forEach((s, aLong) -> {
            while (s != null) {
                SmallTaxTree.SmallTaxIdNode parent = s.getParent();
                if (parent != null) {
                    int r = parent.getRankOrdinal();
                    if (r > 0 && ranksToRefine[r]) {
                        intersectionsPerNode.incSubnodeCounts(s, aLong);
                        break;
                    }
                }
                s = parent;
            }
        });

        set(intersectionsPerNode);
    }

    protected ProgressBar createProgressBar(GSProgressUpdate update) {
        return booleanConfigValue(GSConfigKey.PROGRESS_BAR) ?
                GSProgressBarCreator.newGSProgressBar(getKey().getName(), update.max(), 1000, " kmers", update, getLogger(), true) :
                null;
    }

    public class IntersectionsPerNodeImpl implements IntersectionsPerNode {
        private Set<SmallTaxTree.SmallTaxIdNode> immutableParentNodes;
        private Map<SmallTaxTree.SmallTaxIdNode, long[]> parentToCounts;
        private Map<SmallTaxTree.SmallTaxIdNode, long[]> childToSubnodeCounts;

        public IntersectionsPerNodeImpl() {
            parentToCounts = new HashMap<>();
            childToSubnodeCounts = new HashMap<>();
            immutableParentNodes = Collections.unmodifiableSet(parentToCounts.keySet());
        }

        @Override
        public Set<SmallTaxTree.SmallTaxIdNode> getParentNodes() {
            return immutableParentNodes;
        }

        @Override
        public long getIntersectionCount(SmallTaxTree.SmallTaxIdNode parent, int i, int j) {
            if (i > j) {
                int h = i;
                i = j;
                j = h;
            }
            long[] counts = parentToCounts.get(parent);
            return counts == null ? 0 : counts[(j * j + j) / 2 + i];
        }

        void incSubnodeCounts(SmallTaxTree.SmallTaxIdNode parent, long add) {
            long[] count = childToSubnodeCounts.get(parent);
            if (count == null) {
                count = new long[1];
                childToSubnodeCounts.put(parent, count);
            }
            count[0] += add;
        }

        void incIntersectionCount(SmallTaxTree.SmallTaxIdNode parent, int i, int j) {
            long[] counts = countsForParent(parent);
            if (i > j) {
                int h = i;
                i = j;
                j = h;
            }
            counts[(j * j + j) / 2 + i]++;
        }

        private long[] countsForParent(SmallTaxTree.SmallTaxIdNode parent) {
            long[] counts = parentToCounts.get(parent);
            if (counts == null) {
                // "+ 1" for "OTHER_VALUE", spread and number of k-mers
                int c = parent.getSubNodes().length + 1;
                parentToCounts.put(parent, counts = new long[(c * c + c) / 2 + 2]);
            }
            return counts;
        }

        void incKMerSpread(SmallTaxTree.SmallTaxIdNode parent, int spread) {
            long[] counts = countsForParent(parent);
            counts[counts.length - 2] += spread;
            counts[counts.length - 1]++;
        }

        @Override
        public long getKMerSpreadSum(SmallTaxTree.SmallTaxIdNode parent) {
            long[] counts = parentToCounts.get(parent);
            return counts == null ? 0 : counts[counts.length - 2];
        }

        @Override
        public long getKMerSum(SmallTaxTree.SmallTaxIdNode parent) {
            long[] counts = parentToCounts.get(parent);
            return counts == null ? 0 : counts[counts.length - 1];
        }

        @Override
        public double getJaccardIndex(SmallTaxTree.SmallTaxIdNode parent, int i, int j, boolean withChildCounts) {
            long intersect = getIntersectionCount(parent, i, j);
            long union = getIntersectionCount(parent, i, i) + getIntersectionCount(parent, j, j) - intersect;
            if (withChildCounts) {
                SmallTaxTree.SmallTaxIdNode[] children = parent.getSubNodes();
                if (i < children.length && j < children.length) {
                    union += getSubnodesKMerCount(parent.getSubNodes()[i]);
                    union += getSubnodesKMerCount(parent.getSubNodes()[j]);
                }
            }
            return ((double) intersect) / union;
        }

        @Override
        public double getAvgKMerSpread(SmallTaxTree.SmallTaxIdNode parent) {
            return ((double) getKMerSpreadSum(parent)) / getKMerSum(parent);
        }

        @Override
        public double getOverspreadRatio(SmallTaxTree.SmallTaxIdNode parent) {
            return (getAvgKMerSpread(parent) - 2) / ((parent.getSubNodes().length + 1) - 2);
        }

        @Override
        public long getSubnodesKMerCount(SmallTaxTree.SmallTaxIdNode child) {
            long[] count = childToSubnodeCounts.get(child);
            return count == null ? 0 : count[0];
        }
    }
}
