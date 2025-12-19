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
package org.metagene.genestrip.finertree;

import org.metagene.genestrip.GSGoalKey;
import org.metagene.genestrip.GSMaker;
import org.metagene.genestrip.GSProject;
import org.metagene.genestrip.finertree.cluster.DendrogramNode;
import org.metagene.genestrip.finertree.goals.*;
import org.metagene.genestrip.goals.LoadDBGoal;
import org.metagene.genestrip.goals.refseq.RefSeqFnaFilesDownloadGoal;
import org.metagene.genestrip.goals.refseq.StoreDBGoal;
import org.metagene.genestrip.make.ObjectGoal;
import org.metagene.genestrip.refseq.AccessionMap;
import org.metagene.genestrip.refseq.RefSeqCategory;
import org.metagene.genestrip.store.Database;
import org.metagene.genestrip.tax.SmallTaxTree;
import org.metagene.genestrip.tax.TaxTree;

import java.io.File;
import java.util.*;

public class FinerTreeMaker extends GSMaker {
    public FinerTreeMaker(GSProject project) {
        super(project);
    }

    @Override
    protected void createGoals() {
        super.createGoals();

        ObjectGoal<Set<RefSeqCategory>, GSProject> categoriesGoal = (ObjectGoal<Set<RefSeqCategory>, GSProject>) getGoal(GSGoalKey.CATEGORIES);
        ObjectGoal<Set<TaxTree.TaxIdNode>, GSProject> taxNodesGoal = (ObjectGoal<Set<TaxTree.TaxIdNode>, GSProject>) getGoal(GSGoalKey.TAXNODES);
        ObjectGoal<TaxTree, GSProject> taxTreeGoal = (ObjectGoal<TaxTree, GSProject>) getGoal(GSGoalKey.TAXTREE);
        RefSeqFnaFilesDownloadGoal fnaFilesGoal = (RefSeqFnaFilesDownloadGoal) getGoal(GSGoalKey.REFSEQFNA);
        ObjectGoal<Map<File, TaxTree.TaxIdNode>, GSProject> additionalGoal = (ObjectGoal<Map<File, TaxTree.TaxIdNode>, GSProject>) getGoal(GSGoalKey.ADD_FASTAS);
        ObjectGoal<AccessionMap, GSProject> accessionMapGoal = (ObjectGoal<AccessionMap, GSProject>) getGoal(GSGoalKey.ACCMAP);
        ObjectGoal<Database, GSProject> storeGoal = (ObjectGoal<Database, GSProject>) getGoal(GSGoalKey.LOAD_DB);
        KMerIndexBloomGoal bloomGoal = new KMerIndexBloomGoal(getProject(), getExecutionContext(getProject()),
                categoriesGoal, taxNodesGoal, taxTreeGoal, fnaFilesGoal, additionalGoal, accessionMapGoal, storeGoal);
        registerGoal(bloomGoal);

        StoreKMerIndexGoal storeKMerIndexGoal = new StoreKMerIndexGoal(getProject(), bloomGoal);
        registerGoal(storeKMerIndexGoal);

        LoadKMerIndexGoal loadKMerIndexGoal = new LoadKMerIndexGoal(getProject(), bloomGoal, storeKMerIndexGoal);
        registerGoal(loadKMerIndexGoal);

        KMerIntersectCountGoal intersectCountGoal = new KMerIntersectCountGoal(getProject(), storeGoal, loadKMerIndexGoal);
        registerGoal(intersectCountGoal);

        KMerIntersectCSVGoal csvGoal = new KMerIntersectCSVGoal(getProject(), storeGoal, intersectCountGoal);
        registerGoal(csvGoal);

        ObjectGoal<Map<SmallTaxTree.SmallTaxIdNode, DendrogramNode>, GSProject> dendrogramGoal = new DendrogramGoal(getProject(), intersectCountGoal);
        registerGoal(dendrogramGoal);

        DengrogramLaTeXGoal laTeXGoal = new DengrogramLaTeXGoal(getProject(), storeGoal, dendrogramGoal);
        registerGoal(laTeXGoal);

        UpdateStoreGoal updateStoreGoal = new UpdateStoreGoal(getProject(), storeGoal, dendrogramGoal, loadKMerIndexGoal);
        registerGoal(updateStoreGoal);

        StoreDBGoal storeUpdatedDBGoal = new StoreDBGoal(getProject(), FTGoalKey.FTDB,
                getProject().getOutputFile(FTGoalKey.FTDB.getName(), GSProject.FileType.DB, false), updateStoreGoal);
        registerGoal(storeUpdatedDBGoal);

        LoadDBGoal loadDBGoal = new LoadDBGoal(getProject(), FTGoalKey.LOAD_FTDB, updateStoreGoal, storeUpdatedDBGoal);
        registerGoal(loadDBGoal);

        FTDBInfoGoal infoGoal = new FTDBInfoGoal(getProject(), loadDBGoal);
        registerGoal(infoGoal);
    }
}
