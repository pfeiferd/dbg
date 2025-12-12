package org.metagene.genestrip.finertree.goals;

import org.metagene.genestrip.GSProject;
import org.metagene.genestrip.finertree.FTConfigKey;
import org.metagene.genestrip.finertree.FTGoalKey;
import org.metagene.genestrip.finertree.FinerTreeMaker;
import org.metagene.genestrip.finertree.cluster.DendrogramNode;
import org.metagene.genestrip.finertree.cluster.Similarity;
import org.metagene.genestrip.finertree.cluster.SimpleAggloClustering;
import org.metagene.genestrip.make.Goal;
import org.metagene.genestrip.make.GoalKey;
import org.metagene.genestrip.make.ObjectGoal;
import org.metagene.genestrip.tax.SmallTaxTree;

import java.util.HashMap;
import java.util.Map;

public class DendrogramGoal extends ObjectGoal<Map<SmallTaxTree.SmallTaxIdNode, DendrogramNode>, GSProject> {
    private final ObjectGoal<KMerIntersectCountGoal.IntersectionsPerNode, GSProject> kmerIntersectGoal;

    @SafeVarargs
    public DendrogramGoal(GSProject project, ObjectGoal<KMerIntersectCountGoal.IntersectionsPerNode, GSProject> kmerIntersectGoal, Goal<GSProject>... deps) {
        super(project, FTGoalKey.DENDROGRAM, append(deps, kmerIntersectGoal));
        this.kmerIntersectGoal = kmerIntersectGoal;
    }

    @Override
    protected void doMakeThis() {
        Map<SmallTaxTree.SmallTaxIdNode, DendrogramNode> res = new HashMap<>();
        KMerIntersectCountGoal.IntersectionsPerNode intersections = kmerIntersectGoal.get();
        SimpleAggloClustering.Method method = (SimpleAggloClustering.Method) configValue(FTConfigKey.CLUSTER_METHOD);
        SimpleAggloClustering clustering = new SimpleAggloClustering(method);
        boolean withChildCounts = booleanConfigValue(FTConfigKey.WITH_CHILD_COUNTS);
        for (SmallTaxTree.SmallTaxIdNode parent : intersections.getParentNodes()) {
            DendrogramNode node = clustering.cluster(new Similarity() {
                @Override
                public int values() {
                    int otherPos = parent.getSubNodes().length;
                    long count = intersections.getIntersectionCount(parent, otherPos, otherPos);
                    return  parent.getSubNodes().length + (count == 0 ? 0 : 1); // "+ 1" for "OTHER_VALUE"
                }

                @Override
                public double getSimilarity(int i, int j) {
                    return intersections.getJaccardIndex(parent, i, j, withChildCounts);
                }
            });
            res.put(parent, node);
        }
        set(res);
    }
}
