package org.metagene.genestrip.finertree.goals;

import org.metagene.genestrip.GSProject;
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
    public static GoalKey GOAL_KEY = new GoalKey() {
        @Override
        public String getName() {
            return "dendrogram";
        }
    };

    private final ObjectGoal<KMerIntersectCountGoal.IntersectionsPerNode, GSProject> kmerIntersectGoal;

    @SafeVarargs
    public DendrogramGoal(GSProject project, ObjectGoal<KMerIntersectCountGoal.IntersectionsPerNode, GSProject> kmerIntersectGoal, Goal<GSProject>... deps) {
        super(project, GOAL_KEY, append(deps, kmerIntersectGoal));
        this.kmerIntersectGoal = kmerIntersectGoal;
    }

    @Override
    protected void doMakeThis() {
        Map<SmallTaxTree.SmallTaxIdNode, DendrogramNode> res = new HashMap<>();
        KMerIntersectCountGoal.IntersectionsPerNode intersections = kmerIntersectGoal.get();
        SimpleAggloClustering clustering = new SimpleAggloClustering(SimpleAggloClustering.Method.SINGLE_LINKAGE);
        for (SmallTaxTree.SmallTaxIdNode parent : intersections.getParentNodes()) {
            DendrogramNode node = clustering.cluster(new Similarity() {
                @Override
                public int values() {
                    return parent.getSubNodes().length;
                }

                @Override
                public double getSimilarity(int i, int j) {
                    return intersections.getJaccardIndex(parent, i, j, false);
                }
            });
            res.put(parent, node);
        }
        set(res);
    }
}
