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
        super(project, FTGoalKey.UPDATE_STORE_GOAL, storeGoal, bloomFilterGoal, append(deps, dendrogramGoal));
        this.dendrogramGoal = dendrogramGoal;
    }

    @Override
    protected void beforeKMerStoreWork() {
        // We are going to change the database, so that the original store goal's
        // content becomes invalid:
        cleanStoreGoal();

        orgkMerSortedArray = database.getKmerStore();
        dendrograms = dendrogramGoal.get();
        parentToBitSets = new HashMap<>();
        for (SmallTaxTree.SmallTaxIdNode key : dendrograms.keySet()) {
            DendrogramNode root = dendrograms.get(key);
            if (root != null) {
                if (root.getValueIndex() == -1) {
                    parentToBitSets.put(key, new BitSetsForNodes(key, root));
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
        SmallTaxTree tree = database.getTaxTree();
        // Adjust the small tree at each parent node now:
        // (It must be done later, cause the original tree is still needed in inKMerStoreWork().)
        for (SmallTaxTree.SmallTaxIdNode key : parentToBitSets.keySet()) {
            SmallTaxTree.SmallTaxIdNode[] newSubnodes = new SmallTaxTree.SmallTaxIdNode[2];
            BitSetsForNodes bitSetsForNodes = parentToBitSets.get(key);
            newSubnodes[0] = bitSetsForNodes.child1;
            newSubnodes[1] = bitSetsForNodes.child2;
            tree.setSubNodes(key.getTaxId(), newSubnodes);
        }
        tree.reinitPositions();
        orgkMerSortedArray.fix();

        set(database);
    }

    private class BitSetsForNodes {
        private final SmallTaxTree.SmallTaxIdNode[] orgSubnodes;

        private final boolean[][] bitSets;
        private final SmallTaxTree.SmallTaxIdNode[] nodes;
        private int bitsetPosCounter;
        private final SmallTaxTree.SmallTaxIdNode child1;
        private final SmallTaxTree.SmallTaxIdNode child2;

        public BitSetsForNodes(SmallTaxTree.SmallTaxIdNode parent, DendrogramNode root) {
            this.orgSubnodes = parent.getSubNodes();
            this.bitSets = new boolean[root.size() - 1 - orgSubnodes.length][];
            this.nodes = new SmallTaxTree.SmallTaxIdNode[bitSets.length];

            for (int i = 0; i < bitSets.length; i++) {
                bitSets[i] = new boolean[orgSubnodes.length];
            }
            bitsetPosCounter = 0;
            child1 = createNode(parent, root.getChild1());
            child2 = createNode(parent, root.getChild2());
            bitsetPosCounter = 0;
            initBitSets(root.getChild1());
            initBitSets(root.getChild2());
            sort();
        }

        public void sort() {
            // Very basic max sort is sufficient -
            // unfortunately, standard library methods don't work for this case.
            for (int i = 0; i < bitSets.length; i++) {
                int minIndex = i;
                int minCard = cardinality(bitSets[i]);
                for (int j = i + 1; j < bitSets.length; j++) {
                    int c = cardinality(bitSets[j]);
                    if (c < minCard) {
                        minIndex = j;
                        minCard = c;
                    }
                }
                boolean[] h = bitSets[i];
                bitSets[i] = bitSets[minIndex];
                bitSets[minIndex] = h;
                SmallTaxTree.SmallTaxIdNode hn = nodes[i];
                nodes[i] = nodes[minIndex];
                nodes[minIndex] = hn;
            }
        }

        private int cardinality(boolean[] bits) {
            int cardinality = 0;
            for (int i = 0; i < bits.length; i++) {
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
                if (contained[i] && !container[i]) {
                    return false;
                }
            }
            return true;
        }

        protected SmallTaxTree.SmallTaxIdNode createNode(SmallTaxTree.SmallTaxIdNode parent, DendrogramNode node) {
            int valueIndex = node.getValueIndex();
            if (valueIndex == -1 || valueIndex == orgSubnodes.length) {
                String taxId = "000" + idCounter++;
                short index = orgkMerSortedArray.getAddValueIndex(taxId);
                StringBuilder name = new StringBuilder();
                buildName(node, name);
                SmallTaxTree.SmallTaxIdNode newNode = new SmallTaxTree.SmallTaxIdNode(taxId, name.toString(), Rank.NO_RANK);
                newNode.setStoreIndex(index);
                if (node.getValueIndex() == -1) {
                    nodes[bitsetPosCounter++] = newNode;
                    SmallTaxTree.SmallTaxIdNode[] newSubnodes = new SmallTaxTree.SmallTaxIdNode[2];
                    newSubnodes[0] = createNode(newNode, node.getChild1());
                    newSubnodes[1] = createNode(newNode, node.getChild2());
                    newNode.setSubNodes(newSubnodes);
                } else {
                }
                return newNode;
            } else {
                return orgSubnodes[valueIndex];
            }
        }

        protected void buildName(DendrogramNode node, StringBuilder name) {
            int depth = buildFirstLastName(node, true, name);
            if (depth == 1) {
                name.append('/');
            }
            else if (depth > 1) {
                name.append("/.../");
            }
            if (depth > 0) {
                buildFirstLastName(node, false, name);
            }
        }

        protected int buildFirstLastName(DendrogramNode node, boolean first, StringBuilder name) {
            int index = node.getValueIndex();
            if (index != -1) {
                if (index < orgSubnodes.length) {
                    name.append(orgSubnodes[index].getTaxId());
                }
                else {
                    name.append("OTHER");
                }
                return 0;
            }
            else {
                return buildFirstLastName(first ? node.getChild1() : node.getChild2(), first, name) + 1;
            }
        }

        protected int initBitSets(DendrogramNode node) {
            int valueIndex = node.getValueIndex();
            if (node.getValueIndex() == -1) {
                int res = bitsetPosCounter++;
                int a = initBitSets(node.getChild1());
                int b = initBitSets(node.getChild2());
                boolean[] target = bitSets[res];
                for (int i = 0; i < target.length; i++) {
                    target[i] = ((a < 0) ? (i == -a - 1) : bitSets[a][i]) || ((b < 0) ? (i == -b - 1) : bitSets[b][i]);
                }
                return res;
            } else {
                return -valueIndex - 1;
            }
        }
    }
}
