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
import org.metagene.genestrip.finertree.FinerTreeMaker;
import org.metagene.genestrip.io.StreamProvider;
import org.metagene.genestrip.make.*;
import org.metagene.genestrip.store.Database;
import org.metagene.genestrip.tax.Rank;
import org.metagene.genestrip.tax.SmallTaxTree;

import java.io.File;
import java.io.IOException;
import java.io.PrintStream;
import java.text.DecimalFormat;
import java.text.DecimalFormatSymbols;
import java.util.*;

public class KMerIntersectCSVGoal extends FileListGoal<GSProject> {
    public static GoalKey GOAL_KEY = new GoalKey() {
        @Override
        public String getName() {
            return "intersectcsv";
        }
    };

    private static final DecimalFormat DF = new DecimalFormat("0.00000000", new DecimalFormatSymbols(Locale.US));

    private final ObjectGoal<Database, GSProject> storeGoal;
    private final ObjectGoal<KMerIntersectCountGoal.IntersectionsPerNode, GSProject> kmerIntersectGoal;
    private final Map<File, SmallTaxTree.SmallTaxIdNode> fileToNodeMap;

    @SafeVarargs
    public KMerIntersectCSVGoal(GSProject project, ObjectGoal<Database, GSProject> storeGoal, ObjectGoal<KMerIntersectCountGoal.IntersectionsPerNode, GSProject> kmerIntersectGoal, Goal<GSProject>... deps) {
        super(project, GOAL_KEY, (List<File>) null,  append(deps, kmerIntersectGoal));
        this.storeGoal = storeGoal;
        this.kmerIntersectGoal = kmerIntersectGoal;
        fileToNodeMap = new HashMap<>();
    }

    @Override
    // Do not access kmerIntersectGoal here as it would trigger the related computation already...
    protected void provideFiles() {
        Collection<SmallTaxTree.SmallTaxIdNode> parents = getNodesWithRanks(storeGoal.get().getTaxTree(), (Collection<Rank>) configValue(FinerTreeMaker.REFINEMENT_RANKS));
        for (SmallTaxTree.SmallTaxIdNode node : parents) {
            File matchFile = getProject().getOutputFile(getKey().getName(), node.getTaxId(), null, GSProject.FileType.CSV, false);
            addFile(matchFile);
            fileToNodeMap.put(matchFile, node);
        }
    }

    @Override
    protected void makeFile(File file) throws IOException {
        SmallTaxTree.SmallTaxIdNode parent = fileToNodeMap.get(file);
        KMerIntersectCountGoal.IntersectionsPerNode intersections = kmerIntersectGoal.get();

        try (PrintStream out = new PrintStream(StreamProvider.getOutputStreamForFile(file))) {
            out.println("children; kmer sum; kmer spread sum; avg kmer spread; overspread ratio;");
            int nChildren = parent.getSubNodes().length;
            out.print(nChildren);
            out.print(';');
            out.print(intersections.getKMerSum(parent));
            out.print(';');
            out.print(intersections.getKMerSpreadSum(parent));
            out.print(';');
            out.print(DF.format(intersections.getAvgKMerSpread(parent)));
            out.print(';');
            out.print(DF.format(intersections.getOverspreadRatio(parent)));
            out.print(';');
            out.println();

            SmallTaxTree.SmallTaxIdNode[] children = parent.getSubNodes();
            for (int i = 0; i < children.length; i++) {
                out.print(children[i].getTaxId());
                out.print(';');
            }
            out.println();
            for (int i = 0; i < children.length; i++) {
                for (int j = 0; j < children.length; j++) {
                    out.print(intersections.getIntersectionCount(parent, i, j));
                    out.print(';');
                }
                out.println();
            }
            out.println();
            for (int i = 0; i < children.length; i++) {
                for (int j = 0; j < children.length; j++) {
                    out.print(DF.format(intersections.getJaccardIndex(parent, i, j, false)));
                    out.print(';');
                }
                out.println();
            }
        }
    }

    public static Collection<SmallTaxTree.SmallTaxIdNode> getNodesWithRanks(SmallTaxTree tree, Collection<Rank> ranks) {
        Collection<SmallTaxTree.SmallTaxIdNode> res = new ArrayList<>();
        boolean [] ranksToRefine = new boolean[Rank.values().length];
        for (Rank r : ranks) {
            ranksToRefine[r.ordinal()] = true;
        }

        Iterator<SmallTaxTree.SmallTaxIdNode> it = tree.iterator();
        while (it.hasNext()) {
            SmallTaxTree.SmallTaxIdNode node = it.next();
            Rank r = node.getRank();
            if (r != null && ranksToRefine[r.ordinal()]) {
                if (node.getSubNodes() != null && node.getSubNodes().length > 0) {
                    res.add(node);
                }
            }
        }
        return res;
    }
}
