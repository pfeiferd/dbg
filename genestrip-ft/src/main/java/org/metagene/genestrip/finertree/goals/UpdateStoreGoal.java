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
import org.metagene.genestrip.finertree.FTGoalKey;
import org.metagene.genestrip.finertree.bloom.XORKMerIndexBloomFilter;
import org.metagene.genestrip.finertree.cluster.DendrogramNode;
import org.metagene.genestrip.make.Goal;
import org.metagene.genestrip.make.ObjectGoal;
import org.metagene.genestrip.store.Database;
import org.metagene.genestrip.store.KMerSortedArray;
import org.metagene.genestrip.tax.Rank;
import org.metagene.genestrip.tax.SmallTaxTree;

import java.util.*;

public class UpdateStoreGoal extends KMerStoreWorkGoal<Database> implements Goal.LogHeapInfo {
    private final ObjectGoal<Map<SmallTaxTree.SmallTaxIdNode, DendrogramNode>, GSProject> dendrogramGoal;

    private int idCounter;
    private KMerSortedArray<String> orgkMerSortedArray;
    private Map<SmallTaxTree.SmallTaxIdNode, DendrogramNode> dendrograms;
    private Map<SmallTaxTree.SmallTaxIdNode, BitSetsForNodes> parentToBitSets;

    @SafeVarargs
    public UpdateStoreGoal(GSProject project, ObjectGoal<Database, GSProject> storeGoal, ObjectGoal<Map<SmallTaxTree.SmallTaxIdNode, DendrogramNode>, GSProject> dendrogramGoal, ObjectGoal<XORKMerIndexBloomFilter, GSProject> bloomFilterGoal, Goal<GSProject>... deps) {
        super(project, FTGoalKey.UPDATE_STORE_GOAL, storeGoal, bloomFilterGoal, deps);
        this.dendrogramGoal = dendrogramGoal;
    }

    @Override
    protected void beforeKMerStoreWork() {
        orgkMerSortedArray = storeGoal.get().getKmerStore();
        dendrograms = dendrogramGoal.get();
        parentToBitSets = new HashMap<>();
        for (SmallTaxTree.SmallTaxIdNode key : dendrograms.keySet()) {
            DendrogramNode root = dendrograms.get(key);
            if (root != null) {
                if (root.getValueIndex() == -1) {
                    parentToBitSets.put(key, new BitSetsForNodes(key.getSubNodes(), root));
                } else {
                    // Nothing to do...
                }
            }
        }
    }

    @Override
    protected void inKMerStoreWork(SmallTaxTree.SmallTaxIdNode parent, long pos, boolean[] bits, int spread) {
        BitSetsForNodes bitSetsForNodes = parentToBitSets.get(parent);
        if (bitSetsForNodes != null) {
            SmallTaxTree.SmallTaxIdNode node = bitSetsForNodes.getBestMatchingNode(bits);
            if (node != null) {
                orgkMerSortedArray.setIndexAtPosition(pos, node.getStoreIndex());
            }
        }
    }

    @Override
    protected void afterKMerStoreWork() {
        SmallTaxTree tree = storeGoal.get().getTaxTree();
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

    private class BitSetsForNodes {
        private final SmallTaxTree.SmallTaxIdNode[] orgSubnodes;

        private final boolean[][] bitSets;
        private final SmallTaxTree.SmallTaxIdNode[] nodes;
        private int bitsetPosCounter;

        public BitSetsForNodes(SmallTaxTree.SmallTaxIdNode[] orgSubnodes, DendrogramNode root) {
            this.orgSubnodes = orgSubnodes;
            this.bitSets = new boolean[root.size() - 1 - orgSubnodes.length][];
            this.nodes = new SmallTaxTree.SmallTaxIdNode[bitSets.length];

            for (int i = 0; i < bitSets.length; i++) {
                bitSets[i] = new boolean[orgSubnodes.length];
            }
            bitsetPosCounter = 0;
            createNode(root.getChild1());
            createNode(root.getChild2());
            bitsetPosCounter = 0;
            initBitSets(root.getChild1());
            initBitSets(root.getChild2());
            sort();
        }

        public void sort() {
            // Very basic max sort is sufficient -
            // unfortunately, standard library methods don't work for this case.
            for (int i = 0; i < bitSets.length; i++) {
                int maxIndex = 0;
                int minCard = cardinality(bitSets[i]);
                for (int j = i + 1; j < bitSets.length; j++) {
                    int c = cardinality(bitSets[j]);
                    if (c < minCard) {
                        maxIndex = j;
                        minCard = c;
                    }
                }
                boolean[] h = bitSets[i];
                bitSets[i] = bitSets[maxIndex];
                bitSets[maxIndex] = h;
                SmallTaxTree.SmallTaxIdNode hn = nodes[i];
                nodes[i] = nodes[maxIndex];
                nodes[maxIndex] = hn;
            }
        }

        private int cardinality(boolean[] bits) {
            int cardinality = 0;
            for (int i = 0; i < bitSets.length; i++) {
                if (bits[i]) {
                    cardinality++;
                }
            }
            return cardinality;
        }

        public SmallTaxTree.SmallTaxIdNode getBestMatchingNode(boolean[] bits) {
            short newIndex = -1;
            for (int i = 0; i < bitSets.length; i++) {
                if (contains(bitSets[i], bits)) {
                    return nodes[i];
                }
            }
            return null;
        }

        private boolean contains(boolean[] container, boolean[] contained) {
            for (int i = 0; i < container.length; i++) {
                if (container[i] && !contained[i]) {
                    return false;
                }
            }
            return true;
        }

        protected SmallTaxTree.SmallTaxIdNode createNode(DendrogramNode node) {
            int valueIndex = node.getValueIndex();
            if (valueIndex == -1 || valueIndex == orgSubnodes.length) {
                String taxId = "000" + idCounter++;
                short index = orgkMerSortedArray.getAddValueIndex(taxId);
                SmallTaxTree.SmallTaxIdNode newNode = new SmallTaxTree.SmallTaxIdNode(taxId, Rank.NO_RANK);
                newNode.setStoreIndex(index);
                if (node.getValueIndex() == -1) {
                    nodes[bitsetPosCounter++] = newNode;
                    SmallTaxTree.SmallTaxIdNode[] newSubnodes = new SmallTaxTree.SmallTaxIdNode[2];
                    newNode.setSubNodes(newSubnodes);
                    newSubnodes[0] = createNode(node.getChild1());
                    newSubnodes[1] = createNode(node.getChild2());
                } else {
                }
                return newNode;
            } else {
                return orgSubnodes[valueIndex];
            }
        }

        protected int initBitSets(DendrogramNode node) {
            int valueIndex = node.getValueIndex();
            if (valueIndex == -1 || valueIndex == orgSubnodes.length) {
                if (node.getValueIndex() == -1) {
                    int res = bitsetPosCounter;
                    bitsetPosCounter++;
                    int a = initBitSets(node.getChild1());
                    int b = initBitSets(node.getChild2());
                    boolean[] target = bitSets[bitsetPosCounter];
                    for (int i = 0; i < target.length; i++) {
                        target[i] = ((a < 0) ? (i == -a + 1) : bitSets[a][i]) || ((b < 0) ? (i == -b + 1) : bitSets[b][i]);
                    }
                    return res;
                } else {
                    // "OTHER" case
                    return -orgSubnodes.length - 1;
                }
            } else {
                return -valueIndex - 1;
            }
        }
    }
}
