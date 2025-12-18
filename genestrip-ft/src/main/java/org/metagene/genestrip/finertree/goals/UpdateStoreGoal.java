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

import it.unimi.dsi.fastutil.BigArrays;
import it.unimi.dsi.fastutil.BigSwapper;
import it.unimi.dsi.fastutil.longs.LongComparator;
import me.tongfei.progressbar.ProgressBar;
import org.metagene.genestrip.GSConfigKey;
import org.metagene.genestrip.GSProject;
import org.metagene.genestrip.finertree.FTConfigKey;
import org.metagene.genestrip.finertree.FTGoalKey;
import org.metagene.genestrip.finertree.bloom.XORKMerIndexBloomFilter;
import org.metagene.genestrip.finertree.cluster.DendrogramNode;
import org.metagene.genestrip.make.Goal;
import org.metagene.genestrip.make.ObjectGoal;
import org.metagene.genestrip.store.Database;
import org.metagene.genestrip.store.KMerSortedArray;
import org.metagene.genestrip.tax.Rank;
import org.metagene.genestrip.tax.SmallTaxTree;
import org.metagene.genestrip.util.progressbar.GSProgressBarCreator;
import org.metagene.genestrip.util.progressbar.GSProgressUpdate;

import java.util.*;

public class UpdateStoreGoal extends ObjectGoal<Database, GSProject> implements Goal.LogHeapInfo {
    private static int INITIAL_MAX_CHILDREN = 256;

    private final ObjectGoal<Database, GSProject> storeGoal;
    private final ObjectGoal<Map<SmallTaxTree.SmallTaxIdNode, DendrogramNode>, GSProject> dendrogramGoal;
    private final KMerIndexBloomGoal bloomFilterGoal;
    private final boolean[] ranksToRefine;
    private final List<String> taxidsToRefine;

    private int idCounter;
    private int bitsetPosCounter;
    private KMerSortedArray<String> orgkMerSortedArray;

    @SafeVarargs
    public UpdateStoreGoal(GSProject project, ObjectGoal<Database, GSProject> storeGoal, ObjectGoal<Map<SmallTaxTree.SmallTaxIdNode, DendrogramNode>, GSProject> dendrogramGoal, KMerIndexBloomGoal bloomFilterGoal, Goal<GSProject>... deps) {
        super(project, FTGoalKey.DENDROGRAM, append(deps, storeGoal, dendrogramGoal, bloomFilterGoal));
        this.storeGoal = storeGoal;
        this.dendrogramGoal = dendrogramGoal;
        this.bloomFilterGoal = bloomFilterGoal;
        ranksToRefine = new boolean[Rank.values().length];

        Collection<Rank> toRefine = (Collection<Rank>) configValue(FTConfigKey.REFINEMENT_RANKS);
        for (Rank r : toRefine) {
            ranksToRefine[r.ordinal()] = true;
        }
        taxidsToRefine = (List<String>) configValue(GSConfigKey.TAX_IDS);
    }

    @Override
    protected void doMakeThis() {
        SmallTaxTree tree = storeGoal.get().getTaxTree();

        Map<SmallTaxTree.SmallTaxIdNode, DendrogramNode> dendrograms = dendrogramGoal.get();
        Map<SmallTaxTree.SmallTaxIdNode, BitSetsForNodes> parentToBitSets = new HashMap<>();
        for (SmallTaxTree.SmallTaxIdNode key : dendrograms.keySet()) {
            SmallTaxTree.SmallTaxIdNode[] orgSubnodes = key.getSubNodes();
            DendrogramNode root = dendrograms.get(key);
            if (root != null) {
                if (root.getValueIndex() == -1) {
                    BitSetsForNodes bitSets = new BitSetsForNodes(root.size() - 1, orgSubnodes.length);
                    parentToBitSets.put(key, bitSets);
                    createNode(root.getChild1(), orgSubnodes, bitSets);
                    createNode(root.getChild2(), orgSubnodes, bitSets);
                    bitSets.sort();
                } else {
                    // Nothing to do...
                }
            }
        }

        Database database = storeGoal.get();
        orgkMerSortedArray = database.getKmerStore();
        KMerSortedArray<SmallTaxTree.SmallTaxIdNode> kMerSortedArray = database.convertKMerStore();
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
        XORKMerIndexBloomFilter bloomFilter = bloomFilterGoal.get();
        try (ProgressBar pb = createProgressBar(update)) {
            kMerSortedArray.visit(new KMerSortedArray.KMerSortedArrayVisitor<SmallTaxTree.SmallTaxIdNode>() {
                private BitSet bits = new BitSet();

                @Override
                public void nextValue(KMerSortedArray<SmallTaxTree.SmallTaxIdNode> trie, long kmer, short index, long pos) {
                    current[0] = pos;
                    SmallTaxTree.SmallTaxIdNode parent = kMerSortedArray.getValueForIndex(index);
                    if (parent != null) {
                        int r = parent.getRankOrdinal();
                        if ((r > 0 && ranksToRefine[r]) || taxidsToRefine.contains(parent.getTaxId())) {
                            SmallTaxTree.SmallTaxIdNode[] children = parent.getSubNodes();
                            if (children != null && children.length > 0) {
                                BitSetsForNodes bitSetsForNodes = parentToBitSets.get(parent);
                                if (bitSetsForNodes != null) {
                                    for (int i = 0; i < children.length; i++) {
                                        bits.set(i, checkSubtree(children[i], kmer));
                                    }
                                    bits.set(children.length, bloomFilter.containsLongShort(kmer, KMerIndexBloomGoal.OTHER_VALUE));
                                    SmallTaxTree.SmallTaxIdNode node = bitSetsForNodes.getBestMatchingNode(bits);
                                    if (node != null) {
                                        orgkMerSortedArray.setIndexAtPosition(pos, node.getStoreIndex());
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

        // Adjust the small tree at each parent node now:
        for (SmallTaxTree.SmallTaxIdNode key : parentToBitSets.keySet()) {
            SmallTaxTree.SmallTaxIdNode[] newSubnodes = new SmallTaxTree.SmallTaxIdNode[2];
            SmallTaxTree.SmallTaxIdNode[] nodes = parentToBitSets.get(key).nodes;
            newSubnodes[0] = nodes[nodes.length - 1];
            newSubnodes[1] = nodes[nodes.length - 2];
            tree.setSubNodes(key.getName(), newSubnodes);
        }
        tree.reinitPositions();

        set(storeGoal.get());
    }

    protected ProgressBar createProgressBar(GSProgressUpdate update) {
        return booleanConfigValue(GSConfigKey.PROGRESS_BAR) ?
                GSProgressBarCreator.newGSProgressBar(getKey().getName(), update.max(), 1000, " kmers", update, getLogger(), true) :
                null;
    }

    protected SmallTaxTree.SmallTaxIdNode createNode(DendrogramNode node, SmallTaxTree.SmallTaxIdNode[] orgSubnodes, BitSetsForNodes bitSets) {
        if (node.getValueIndex() == -1) {
            String taxId = "000" + idCounter++;
            short index = orgkMerSortedArray.getAddValueIndex(taxId);
            SmallTaxTree.SmallTaxIdNode newNode = new SmallTaxTree.SmallTaxIdNode(taxId, Rank.NO_RANK);
            newNode.setStoreIndex(index);
            SmallTaxTree.SmallTaxIdNode[] newSubnodes = new SmallTaxTree.SmallTaxIdNode[2];
            newNode.setSubNodes(newSubnodes);
            int oldCounter1 = bitSets.currentIndex();
            newSubnodes[0] = createNode(node.getChild1(), orgSubnodes, bitSets);
            int oldCounter2 = bitSets.currentIndex();
            newSubnodes[1] = createNode(node.getChild2(), orgSubnodes, bitSets);
            return bitSets.initNextNode(newNode, oldCounter1, oldCounter2);
        } else {
            return bitSets.initNextNode(orgSubnodes[node.getValueIndex()], node.getValueIndex());
        }
    }

    private static class BitSetsForNodes {
        private final BitSet[] bitSets;
        private final SmallTaxTree.SmallTaxIdNode[] nodes;
        private int bitsetPosCounter;

        public BitSetsForNodes(int nBitSets, int nNodes) {
            this.bitSets = new BitSet[nBitSets];
            this.nodes = new SmallTaxTree.SmallTaxIdNode[nNodes];

            for (int i = 0; i < bitSets.length; i++) {
                bitSets[i] = new BitSet(nNodes);
            }
            bitsetPosCounter = 0;
        }

        public void sort() {
            // Very basic max sort is sufficient -
            // unfortunateld, standard library methods don't work for this case.
            for (int i = 0; i < bitSets.length; i++) {
                int maxIndex = 0;
                int minCard = bitSets[i].cardinality();
                for (int j = i + 1; i < bitSets.length; j++) {
                    if (bitSets[j].cardinality() < minCard) {
                        maxIndex = j;
                        minCard = bitSets[j].cardinality();
                    }
                }
                BitSet h = bitSets[i];
                bitSets[i] = bitSets[maxIndex];
                bitSets[maxIndex] = h;
                SmallTaxTree.SmallTaxIdNode hn = nodes[i];
                nodes[i] = nodes[maxIndex];
                nodes[maxIndex] = hn;
            }
        }

        public int currentIndex() {
            return bitsetPosCounter;
        }

        public SmallTaxTree.SmallTaxIdNode initNextNode(SmallTaxTree.SmallTaxIdNode node, int a, int b) {
            nodes[bitsetPosCounter] = node;
            bitSets[bitsetPosCounter].or(bitSets[a]);
            bitSets[bitsetPosCounter].or(bitSets[b]);
            bitsetPosCounter++;
            return node;
        }

        public SmallTaxTree.SmallTaxIdNode initNextNode(SmallTaxTree.SmallTaxIdNode node, int bit) {
            nodes[bitsetPosCounter] = node;
            bitSets[bitsetPosCounter].set(bit);
            bitsetPosCounter++;
            return node;
        }

        public SmallTaxTree.SmallTaxIdNode getBestMatchingNode(BitSet bits) {
            short newIndex = -1;
            for (int i = 0; i < bitSets.length; i++) {
                if (contains(bitSets[i], bits)) {
                    return nodes[i];
                }
                ;
            }
            return null;
        }

        private boolean contains(BitSet container, BitSet contained) {
            for (int i = 0; i < container.length(); i++) {
                if (container.get(i) && !contained.get(i)) {
                    return false;
                }
            }
            return true;
        }
    }
}
