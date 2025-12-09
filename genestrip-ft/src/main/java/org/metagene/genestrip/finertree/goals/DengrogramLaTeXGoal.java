package org.metagene.genestrip.finertree.goals;

import org.metagene.genestrip.GSProject;
import org.metagene.genestrip.finertree.FinerTreeMaker;
import org.metagene.genestrip.finertree.cluster.DendrogramNode;
import org.metagene.genestrip.io.StreamProvider;
import org.metagene.genestrip.make.FileListGoal;
import org.metagene.genestrip.make.Goal;
import org.metagene.genestrip.make.GoalKey;
import org.metagene.genestrip.make.ObjectGoal;
import org.metagene.genestrip.store.Database;
import org.metagene.genestrip.tax.Rank;
import org.metagene.genestrip.tax.SmallTaxTree;

import java.io.File;
import java.io.IOException;
import java.io.PrintStream;
import java.text.DecimalFormat;
import java.text.DecimalFormatSymbols;
import java.util.*;

public class DengrogramLaTeXGoal extends FileListGoal<GSProject> {
    public static GoalKey GOAL_KEY = new GoalKey() {
        @Override
        public String getName() {
            return "dendrolatex";
        }
    };

    private static final DecimalFormat DF = new DecimalFormat("0.000000", new DecimalFormatSymbols(Locale.US));
    private static final DecimalFormat DF2 = new DecimalFormat("0.00", new DecimalFormatSymbols(Locale.US));

    private final ObjectGoal<Database, GSProject> storeGoal;
    private final ObjectGoal<Map<SmallTaxTree.SmallTaxIdNode, DendrogramNode>, GSProject> dendrogramGoal;
    private final Map<File, SmallTaxTree.SmallTaxIdNode> fileToNodeMap;

    public DengrogramLaTeXGoal(GSProject project, ObjectGoal<Database, GSProject> storeGoal, ObjectGoal<Map<SmallTaxTree.SmallTaxIdNode, DendrogramNode>, GSProject> dendrogramGoal, Goal<GSProject>... deps) {
        super(project, GOAL_KEY, (List<File>) null, append(deps, storeGoal, dendrogramGoal));
        this.storeGoal = storeGoal;
        this.dendrogramGoal = dendrogramGoal;
        fileToNodeMap = new HashMap<>();
    }

    @Override
    // Do not access kmerIntersectGoal here as it would trigger the related computation already...
    protected void provideFiles() {
        Collection<SmallTaxTree.SmallTaxIdNode> parents = KMerIntersectCSVGoal.getNodesWithRanks(storeGoal.get().getTaxTree(), (Collection<Rank>) configValue(FinerTreeMaker.REFINEMENT_RANKS));
        for (SmallTaxTree.SmallTaxIdNode node : parents) {
            // TODO: A CSV file for LatTeX is not really ideal...
            File matchFile = getProject().getOutputFile(getKey().getName(), node.getTaxId(), null, GSProject.FileType.CSV, false);
            addFile(matchFile);
            fileToNodeMap.put(matchFile, node);
        }
    }

    @Override
    protected void makeFile(File file) throws IOException {
        SmallTaxTree.SmallTaxIdNode parent = fileToNodeMap.get(file);
        DendrogramNode dendrogram = dendrogramGoal.get().get(parent);

        double offset = 0; // children.length / 2;
        double yScaleFactor = 4;
        double xScaleFactor = 1;

        try (PrintStream out = new PrintStream(StreamProvider.getOutputStreamForFile(file))) {
            out.println("\\begin{tikzpicture}[sloped][scale=1]");
            drawAxis(out, xScaleFactor, yScaleFactor, offset);
            drawDendrogram(out, parent, dendrogram, xScaleFactor, yScaleFactor, offset);
            out.println("\\end{tikzpicture}");
        }
    }

    protected void drawDendrogram(PrintStream out, SmallTaxTree.SmallTaxIdNode parent, DendrogramNode dendrogram, double xScaleFactor, double yScaleFactor, double offset) {
        if (dendrogram == null) {
            return;
        }
        SmallTaxTree.SmallTaxIdNode[] children = parent.getSubNodes();
        int[] leafCounter = new int[1];
        int[] preCounter = new int[1];
        dendrogram.visit(new DendrogramNode.Visitor() {
            @Override
            public void preNode(DendrogramNode node) {
                node.setValue(new IntDouble(preCounter[0], leafCounter[0]));
                if (node.getValueIndex() >= 0) {
                    SmallTaxTree.SmallTaxIdNode child = children[node.getValueIndex()];
                    out.print("\\node [rotate=90,anchor=east] (n");
                    out.print(preCounter[0]);
                    out.print(") at (");
                    out.print(DF.format(xScaleFactor * (leafCounter[0] - offset)));
                    out.print(",0) {");
                    out.print(child.getName());
                    out.print(" (");
                    out.print(child.getTaxId());
                    out.println(")};");
                    leafCounter[0]++;
                }
                preCounter[0]++;
            }

            public void postNode(DendrogramNode node) {
                if (node.getValueIndex() == -1) {
                    double xPos = (((IntDouble) node.getChild1().getValue()).d + ((IntDouble) node.getChild2().getValue()).d) / 2;
                    IntDouble value = (IntDouble) node.getValue();
                    value.d = xPos;
                    out.print("\\node (n");
                    out.print(value.i);
                    out.print(") at (");
                    out.print(DF.format(xScaleFactor * (xPos - offset)));
                    out.print(",");
                    out.print(DF.format(yScaleFactor * (1 - node.getSimilarity())));
                    out.println(") {};");
                }
            }
        });
        preCounter[0] = 0;
        dendrogram.visit(new DendrogramNode.Visitor() {
            @Override
            public void preNode(DendrogramNode node) {
                if (node.getValueIndex() == -1) {
                    out.print("\\draw  (n");
                    out.print(((IntDouble) node.getChild1().getValue()).i);
                    if (node.getChild1().getValueIndex() == -1) {
                        out.print(".center");
                    }
                    out.print(") |- (n");
                    out.print(((IntDouble) node.getValue()).i);
                    out.println(".center);");
                    out.print("\\draw  (n");
                    out.print(((IntDouble) node.getChild2().getValue()).i);
                    if (node.getChild2().getValueIndex() == -1) {
                        out.print(".center");
                    }
                    out.print(") |- (n");
                    out.print(((IntDouble) node.getValue()).i);
                    out.println(".center);");
                }
            }

            @Override
            public void postNode(DendrogramNode node) {
            }
        });
    }

    protected void drawAxis(PrintStream out, double xScaleFactor, double yScaleFactor, double offset) {
        double xPos = xScaleFactor * (- offset - 3);
        double yPos = yScaleFactor * 1;
        out.print("\\draw[<-] (");
        out.print(DF.format(xPos));
        out.print(",0) -- node[above]{Similarity} (");
        out.print(DF.format(xPos));
        out.print(",");
        out.print(DF.format(yPos));
        out.println(");");

        xPos = xScaleFactor * (- offset - 1);
        out.print("\\draw (");
        out.print(DF.format(xPos));
        out.print(",0) -- (");
        out.print(DF.format(xPos));
        out.print(",");
        out.print(DF.format(yPos));
        out.println(");");

        int max = 5;
        double xPosLeft = xScaleFactor * (-0.1 - offset - 1);
        for (int i = 0; i <= max; i++) {
            yPos = (yScaleFactor * i) / max;
            out.print("\\draw (");
            out.print(DF.format(xPos));
            out.print(",");
            out.print(DF.format(yPos));
            out.print(") -- (");
            out.print(DF.format(xPosLeft));
            out.print(",");
            out.print(DF.format(yPos));
            out.println(");");

            out.print("\\node[left] at (");
            out.print(DF.format(xPosLeft));
            out.print(",");
            out.print(DF.format(yPos));
            out.print(") {$");
            out.print(DF2.format(((double)(max - i)) / max));
            out.println("$};");
        }
    }

    private static class IntDouble {
        public IntDouble(int i, double d) {
            this.i = i;
            this.d = d;
        }

        public int i;
        public double d;
    }
}