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
import org.metagene.genestrip.finertree.bloom.XORKMerIndexBloomFilter;
import org.metagene.genestrip.make.Goal;
import org.metagene.genestrip.make.ObjectGoal;
import org.metagene.genestrip.store.Database;
import org.metagene.genestrip.store.KMerSortedArray;
import org.metagene.genestrip.tax.Rank;
import org.metagene.genestrip.tax.SmallTaxTree;
import org.metagene.genestrip.util.progressbar.GSProgressBarCreator;
import org.metagene.genestrip.util.progressbar.GSProgressUpdate;

import java.util.Collection;
import java.util.List;

public abstract class KMerStoreWorkGoal<T> extends ObjectGoal<T, GSProject> {
    private static int INITIAL_MAX_CHILDREN = 256;

    protected final ObjectGoal<Database, GSProject> storeGoal;
    protected final ObjectGoal<XORKMerIndexBloomFilter, GSProject> bloomFilterGoal;
    protected final boolean [] ranksToRefine;
    protected final List<String> taxidsToRefine;
    protected KMerSortedArray<SmallTaxTree.SmallTaxIdNode> kMerSortedArray;
    protected XORKMerIndexBloomFilter bloomFilter;

    @SafeVarargs
    public KMerStoreWorkGoal(GSProject project, FTGoalKey goalKey, ObjectGoal<Database, GSProject> storeGoal,
                                  ObjectGoal<XORKMerIndexBloomFilter, GSProject> bloomFilterGoal,
                                  Goal<GSProject>... deps) {
        super(project, goalKey, Goal.append(deps, storeGoal, bloomFilterGoal));
        this.storeGoal = storeGoal;
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
        kMerSortedArray = storeGoal.get().convertKMerStore();
        bloomFilter = bloomFilterGoal.get();

        beforeKMerStoreWork();

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
                        int r = parent.getRankOrdinal();
                        if ((r > 0 && ranksToRefine[r]) || taxidsToRefine.contains(parent.getTaxId())) {
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
                                inKMerStoreWork(parent, pos, bits, spread);
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

        afterKMerStoreWork();
    }

    protected abstract void beforeKMerStoreWork();

    protected abstract void inKMerStoreWork(SmallTaxTree.SmallTaxIdNode parent, long pos, boolean[] bits, int spread);

    protected abstract void afterKMerStoreWork();

    protected ProgressBar createProgressBar(GSProgressUpdate update) {
        return booleanConfigValue(GSConfigKey.PROGRESS_BAR) ?
                GSProgressBarCreator.newGSProgressBar(getKey().getName(), update.max(), 1000, " kmers", update, null, true) :
                null;
    }
}
