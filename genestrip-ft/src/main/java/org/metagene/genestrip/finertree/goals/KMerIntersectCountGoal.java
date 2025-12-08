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

import org.metagene.genestrip.GSProject;
import org.metagene.genestrip.finertree.FinerTreeGSMaker;
import org.metagene.genestrip.finertree.bloom.XORKMerIndexBloomFilter;
import org.metagene.genestrip.make.Goal;
import org.metagene.genestrip.make.GoalKey;
import org.metagene.genestrip.make.ObjectGoal;
import org.metagene.genestrip.store.Database;
import org.metagene.genestrip.store.KMerSortedArray;
import org.metagene.genestrip.tax.Rank;
import org.metagene.genestrip.tax.SmallTaxTree;

import java.util.*;

public class KMerIntersectCountGoal extends ObjectGoal<KMerIntersectCountGoal.IntersectionsPerNode, GSProject> {
    public interface IntersectionsPerNode  {
        public Set<SmallTaxTree.SmallTaxIdNode> getParentNodes();
        public long getIntersectionCount(SmallTaxTree.SmallTaxIdNode parent, int child1, int child2);
        public long getKMerSpreadSum(SmallTaxTree.SmallTaxIdNode parent);
        public long getKMerSum(SmallTaxTree.SmallTaxIdNode parent);
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
        super(project, GOAL_KEY, Goal.append(deps, storeGoal, bloomFilterGoal));
        this.storeGoal = storeGoal;
        this.bloomFilterGoal = bloomFilterGoal;
    }

    @Override
    protected void doMakeThis() {
        boolean [] ranksToRefine = new boolean[Rank.values().length];
        Collection<Rank> toRefine = (Collection<Rank>) configValue(FinerTreeGSMaker.REFINEMENT_RANKS);
        for (Rank r : toRefine) {
            ranksToRefine[r.ordinal()] = true;
        }
        SmallTaxTree tree = storeGoal.get().getTaxTree();
        KMerSortedArray<SmallTaxTree.SmallTaxIdNode> kMerSortedArray = storeGoal.get().convertKMerStore();
        XORKMerIndexBloomFilter bloomFilter = bloomFilterGoal.get();

        IntersectionsPerNodeImpl intersectionsPerNode = new IntersectionsPerNodeImpl();
        kMerSortedArray.visit(new KMerSortedArray.KMerSortedArrayVisitor<SmallTaxTree.SmallTaxIdNode>() {
            private boolean[] bits = new boolean[INITIAL_MAX_CHILDREN];

            @Override
            public void nextValue(KMerSortedArray<SmallTaxTree.SmallTaxIdNode> trie, long kmer, short index, long pos) {
                SmallTaxTree.SmallTaxIdNode parent = kMerSortedArray.getValueForIndex(index);
                if (parent != null) {
                    if (ranksToRefine[parent.getRank().ordinal()]) {
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
                            for (int i = 0; i < children.length; i++) {
                                for (int j = i; j < children.length; j++) {
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
        set(intersectionsPerNode);
    }

    public class IntersectionsPerNodeImpl implements IntersectionsPerNode {
        private Set<SmallTaxTree.SmallTaxIdNode> immutableParentNodes;
        private Map<SmallTaxTree.SmallTaxIdNode, long[]> parentToCounts;

        public IntersectionsPerNodeImpl() {
            parentToCounts = new HashMap<>();
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
                int c = parent.getSubNodes().length;
                parentToCounts.put(parent, counts = new long[(c * c + c) / 2 + 2]);
            }
            return counts;
        }

        void incKMerSpread(SmallTaxTree.SmallTaxIdNode parent, int spread) {
            long[] counts = countsForParent(parent);
            counts[counts.length - 2] += spread;
            counts[counts.length - 1]++;
        }

        public long getKMerSpreadSum(SmallTaxTree.SmallTaxIdNode parent) {
            long[] counts = parentToCounts.get(parent);
            return counts == null ? 0 : counts[counts.length - 2];
        }

        public long getKMerSum(SmallTaxTree.SmallTaxIdNode parent) {
            long[] counts = parentToCounts.get(parent);
            return counts == null ? 0 : counts[counts.length - 1];
        }
    }
}
