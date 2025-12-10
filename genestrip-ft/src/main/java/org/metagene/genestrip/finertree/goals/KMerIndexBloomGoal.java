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
import it.unimi.dsi.fastutil.shorts.Short2IntMap;
import it.unimi.dsi.fastutil.shorts.Short2LongMap;
import org.metagene.genestrip.ExecutionContext;
import org.metagene.genestrip.GSConfigKey;
import org.metagene.genestrip.GSProject;
import org.metagene.genestrip.finertree.FinerTreeMaker;
import org.metagene.genestrip.finertree.bloom.XORKMerIndexBloomFilter;
import org.metagene.genestrip.goals.refseq.FastaReaderGoal;
import org.metagene.genestrip.goals.refseq.RefSeqFnaFilesDownloadGoal;
import org.metagene.genestrip.make.Goal;
import org.metagene.genestrip.make.GoalKey;
import org.metagene.genestrip.make.ObjectGoal;
import org.metagene.genestrip.refseq.AbstractRefSeqFastaReader;
import org.metagene.genestrip.refseq.AbstractStoreFastaReader;
import org.metagene.genestrip.refseq.AccessionMap;
import org.metagene.genestrip.refseq.RefSeqCategory;
import org.metagene.genestrip.store.Database;
import org.metagene.genestrip.store.KMerSortedArray;
import org.metagene.genestrip.tax.Rank;
import org.metagene.genestrip.tax.SmallTaxTree;
import org.metagene.genestrip.tax.TaxTree;

import java.io.File;
import java.io.IOException;
import java.util.Collection;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

public class KMerIndexBloomGoal extends FastaReaderGoal<XORKMerIndexBloomFilter> implements Goal.LogHeapInfo {
    public static GoalKey GOAL_KEY = new GoalKey() {
        @Override
        public String getName() {
            return "kmerindexbloom";
        }
    };

    private final ObjectGoal<AccessionMap, GSProject> accessionMapGoal;
    private final ObjectGoal<Database, GSProject> storeGoal;
    private final boolean multiThreading;
    private final boolean[] ranksToRefine;

    private KMerSortedArray<SmallTaxTree.SmallTaxIdNode> kMerSortedArray;
    private SmallTaxTree smallTaxTree;
    private XORKMerIndexBloomFilter filter;

    @SafeVarargs
    public KMerIndexBloomGoal(GSProject project, ExecutionContext bundle, ObjectGoal<Set<RefSeqCategory>, GSProject> categoriesGoal,
                  ObjectGoal<Set<TaxTree.TaxIdNode>, GSProject> taxNodesGoal,
                  ObjectGoal<TaxTree, GSProject> taxTreeGoal, RefSeqFnaFilesDownloadGoal fnaFilesGoal,
                  ObjectGoal<Map<File, TaxTree.TaxIdNode>, GSProject> additionalGoal,
                  ObjectGoal<AccessionMap, GSProject> accessionMapGoal, ObjectGoal<Database, GSProject> storeGoal,
                  Goal<GSProject>... deps) {
        super(project, GOAL_KEY, bundle, categoriesGoal, taxNodesGoal, fnaFilesGoal, additionalGoal, Goal.append(deps, taxTreeGoal, accessionMapGoal, storeGoal));
        this.storeGoal = storeGoal;
        this.accessionMapGoal = accessionMapGoal;
        multiThreading = bundle.getThreads() > 0;
        ranksToRefine = new boolean[Rank.values().length];
        Collection<Rank> toRefine = (Collection<Rank>) configValue(FinerTreeMaker.REFINEMENT_RANKS);
        for (Rank r : toRefine) {
            ranksToRefine[r.ordinal()] = true;
        }
    }

    @Override
    protected void doMakeThis() {
        try {
            smallTaxTree = storeGoal.get().getTaxTree();
            kMerSortedArray = storeGoal.get().convertKMerStore();
            Object2LongMap<SmallTaxTree.SmallTaxIdNode> stats = kMerSortedArray.getNKmersPerTaxid();
            long[] counter = new long[1];
            stats.forEach((s, aLong) -> {
                if (s != null) {
                    Rank r = s.getRank();
                    if (r != null && ranksToRefine[r.ordinal()]) {
                        // Conservative estimate: k-mer could be in genome of every subnode, i.e. species...
                        counter[0] += aLong * s.getSubNodes().length;
                    }
                }
            });
            filter = new XORKMerIndexBloomFilter(intConfigValue(GSConfigKey.KMER_SIZE),
                    doubleConfigValue(GSConfigKey.TEMP_BLOOM_FILTER_FPP));
            filter.ensureExpectedSize(counter[0], false);
            readFastas();
            set(filter);
            if (getLogger().isInfoEnabled()) {
                getLogger().info("Maximum expected filter entries: " + counter[0]);
                getLogger().info("Actual filter entries: " + filter.getEntries());
            }
        } catch (IOException e) {
            throw new RuntimeException(e);
        } finally {
            cleanUpThreads();
        }
    }

    @Override
    protected AbstractStoreFastaReader createFastaReader(AbstractRefSeqFastaReader.StringLong2DigitTrie regionsPerTaxid) {
        return new MyFastaReader(intConfigValue(GSConfigKey.FASTA_LINE_SIZE_BYTES),
                taxNodesGoal.get(),
                isIncludeRefSeqFna() ? accessionMapGoal.get() : null,
                intConfigValue(GSConfigKey.MAX_GENOMES_PER_TAXID),
                (Rank) configValue(GSConfigKey.MAX_GENOMES_PER_TAXID_RANK),
                longConfigValue(GSConfigKey.MAX_KMERS_PER_TAXID),
                intConfigValue(GSConfigKey.MAX_DUST),
                intConfigValue(GSConfigKey.STEP_SIZE),
                booleanConfigValue(GSConfigKey.COMPLETE_GENOMES_ONLY),
                regionsPerTaxid,
                booleanConfigValue(GSConfigKey.ENABLE_LOWERCASE_BASES));
    }

    protected class MyFastaReader extends AbstractStoreFastaReader {
        private SmallTaxTree.SmallTaxIdNode smallNode;

        public MyFastaReader(int bufferSize, Set<TaxTree.TaxIdNode> taxNodes, AccessionMap accessionMap,
                             int maxGenomesPerTaxId, Rank maxGenomesPerTaxIdRank, long maxKmersPerTaxId, int maxDust, int stepSize, boolean completeGenomesOnly, StringLong2DigitTrie regionsPerTaxid, boolean enableLowerCaseBases) {
            super(bufferSize, taxNodes, accessionMap, filter.getK(), maxGenomesPerTaxId, maxGenomesPerTaxIdRank, maxKmersPerTaxId, maxDust, stepSize, completeGenomesOnly, regionsPerTaxid, enableLowerCaseBases);
        }

        @Override
        protected void infoLine() {
            if (ignoreMap) {
                node = mappedNode;
            }
            else {
                updateNodeFromInfoLine();
            }

            if (node != null && (taxNodes.isEmpty() || taxNodes.contains(node))) {
                node = reworkNode();
                if (node != null) {
                    smallNode = smallTaxTree.getNodeByTaxId(node.getTaxId());
                    if (smallNode != null) {
                        includeRegion = true;
                    }
                }
                else {
                    smallNode = null;
                }
            }
        }

        @Override
        protected void endRegion() {
            // Intentionally empty.
        }

        @Override
        public boolean isAllowMoreKmers() {
            return true;
        }

        @Override
        protected boolean handleStore() {
            long kmer = byteRingBuffer.getStandardKMer();
            SmallTaxTree.SmallTaxIdNode storedNode = kMerSortedArray.getLong(kmer, null);
            if (storedNode != null && ranksToRefine[storedNode.getRank().ordinal()]) {
                short index = smallNode.storeIndex;
                if (!filter.containsLongShort(kmer, index)) {
                    if (multiThreading) {
                        synchronized (filter) {
                            // This is a trick to enable more parallelism -
                            // check again after synchronized to avoid synchronized further outside...
                            if (!filter.containsLongShort(kmer, index)) {
                                filter.putLongShort(kmer, index);
                                return true;
                            }
                        }
                    } else {
                        filter.putLongShort(kmer, index);
                        return true;
                    }
                }
            }
            return false;
        }
    }
}
