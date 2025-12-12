package org.metagene.genestrip.finertree.goals;

import org.metagene.genestrip.GSProject;
import org.metagene.genestrip.finertree.FTConfigKey;
import org.metagene.genestrip.finertree.FTGoalKey;
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
    private static final DecimalFormat DF = new DecimalFormat("0.000000", new DecimalFormatSymbols(Locale.US));
    private static final DecimalFormat DF2 = new DecimalFormat("0.00", new DecimalFormatSymbols(Locale.US));

    private final ObjectGoal<Database, GSProject> storeGoal;
    private final ObjectGoal<Map<SmallTaxTree.SmallTaxIdNode, DendrogramNode>, GSProject> dendrogramGoal;
    private final Map<File, SmallTaxTree.SmallTaxIdNode> fileToNodeMap;

    public DengrogramLaTeXGoal(GSProject project, ObjectGoal<Database, GSProject> storeGoal, ObjectGoal<Map<SmallTaxTree.SmallTaxIdNode, DendrogramNode>, GSProject> dendrogramGoal, Goal<GSProject>... deps) {
        super(project, FTGoalKey.DENDRO_LATEX, (List<File>) null, append(deps, storeGoal, dendrogramGoal));
        this.storeGoal = storeGoal;
        this.dendrogramGoal = dendrogramGoal;
        fileToNodeMap = new HashMap<>();
    }

    @Override
    // Do not access kmerIntersectGoal here as it would trigger the related computation already...
    protected void provideFiles() {
        Collection<SmallTaxTree.SmallTaxIdNode> parents = KMerIntersectCSVGoal.getNodesWithRanks(storeGoal.get().getTaxTree(), (Collection<Rank>) configValue(FTConfigKey.REFINEMENT_RANKS));
        for (SmallTaxTree.SmallTaxIdNode node : parents) {
            File matchFile = getProject().getOutputFile(getKey().getName(), node.getTaxId(), null, GSProject.FileType.TXT, false);
            addFile(matchFile);
            fileToNodeMap.put(matchFile, node);
        }
    }

    @Override
    protected void makeFile(File file) throws IOException {
        SmallTaxTree.SmallTaxIdNode parent = fileToNodeMap.get(file);
        DendrogramNode dendrogram = dendrogramGoal.get().get(parent);

        double yScaleFactor = doubleConfigValue(FTConfigKey.Y_FACTOR_LATEX);
        double xScaleFactor = doubleConfigValue(FTConfigKey.X_FACTOR_LATEX);
        boolean turn = booleanConfigValue(FTConfigKey.TURN_LATEX);

        try (PrintStream out = new PrintStream(StreamProvider.getOutputStreamForFile(file))) {
            out.println("\\begin{tikzpicture}[sloped,scale=1]");
            drawAxis(out, xScaleFactor, yScaleFactor, turn);
            drawDendrogram(out, parent, dendrogram, xScaleFactor, yScaleFactor, turn);
            out.println("\\end{tikzpicture}");
        }
    }

    protected void drawDendrogram(PrintStream out, SmallTaxTree.SmallTaxIdNode parent, DendrogramNode dendrogram, double xScaleFactor, double yScaleFactor, boolean turn) {
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
                int index = node.getValueIndex();
                if (index >= 0) {
                    out.print("\\node ");
                    if (!turn) {
                        out.print("[rotate=90,anchor=east] ");
                    }
                    else {
                        out.print("[anchor=east] ");
                    }
                    out.print("(n");
                    out.print(preCounter[0]);
                    out.print(") at (");
                    if (turn) {
                        out.print("0,");
                    }
                    out.print(DF.format(xScaleFactor * leafCounter[0]));
                    if (!turn) {
                        out.print(",0");
                    }
                    out.print(") {");
                    if (index < children.length) {
                        out.print(children[index].getName());
                        out.print(" (");
                        out.print(children[index].getTaxId());
                        out.println(");");
                    }
                    else {
                        out.print("OTHER");
                    }
                    out.println("};");
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
                    if (turn) {
                        out.print(DF.format(yScaleFactor * (1 - node.getSimilarity())));
                        out.print(",");
                        out.print(DF.format(xScaleFactor * xPos));
                    }
                    else {
                        out.print(DF.format(xScaleFactor * xPos));
                        out.print(",");
                        out.print(DF.format(yScaleFactor * (1 - node.getSimilarity())));
                    }
                    out.println(") {};");
                }
            }
        });
        preCounter[0] = 0;
        dendrogram.visit(new DendrogramNode.Visitor() {
            @Override
            public void preNode(DendrogramNode node) {
                if (node.getValueIndex() == -1) {
                    if (turn) {
                        drawEdge(node, node.getChild1(), turn);
                        drawEdge(node, node.getChild2(), turn);
                    }
                    else {
                        drawEdge(node.getChild1(), node, turn);
                        drawEdge(node.getChild2(), node, turn);
                    }
                }
            }

            protected void drawEdge(DendrogramNode from, DendrogramNode to, boolean turn) {
                out.print("\\draw  (n");
                out.print(((IntDouble) from.getValue()).i);
                if (from.getValueIndex() == -1) {
                    out.print(".center");
                }
                else if (turn) {
                    out.print(".east");
                }
                out.print(") |- (n");
                out.print(((IntDouble) to.getValue()).i);
                if (to.getValueIndex() == -1) {
                    out.print(".center");
                }
                else if (turn) {
                    out.print(".east");
                }
                out.println(");");
            }

            @Override
            public void postNode(DendrogramNode node) {
            }
        });
    }

    protected void drawAxis(PrintStream out, double xScaleFactor, double yScaleFactor, boolean turn) {
        double xPos = -xScaleFactor -1.5;
        double yPos = yScaleFactor;
        out.print("\\draw[<-] (");
        out.print(turn ? "0" : DF.format(xPos));
        out.print(",");
        out.print(turn ? DF.format(xPos) : "0");
        out.print(") -- node[above]{Similarity} (");
        out.print(DF.format(turn ? yPos: xPos));
        out.print(",");
        out.print(DF.format(turn ? xPos : yPos));
        out.println(");");

        xPos = -xScaleFactor;
        out.print("\\draw (");
        out.print(turn ? "0" : DF.format(xPos));
        out.print(",");
        out.print(turn ? DF.format(xPos) : "0");
        out.print(") -- (");
        out.print(DF.format(turn ? yPos : xPos));
        out.print(",");
        out.print(DF.format(turn ? xPos : yPos));
        out.println(");");

        int max = 5;
        for (int i = 0; i <= max; i++) {
            double xPosLeft = -xScaleFactor - 0.1;
            yPos = (yScaleFactor * i) / max;
            out.print("\\draw (");
            out.print(DF.format(turn ? yPos : xPos));
            out.print(",");
            out.print(DF.format(turn ? xPos : yPos));
            out.print(") -- (");
            out.print(DF.format(turn ? yPos : xPosLeft));
            out.print(",");
            out.print(DF.format(turn ? xPosLeft : yPos));
            out.println(");");

            xPosLeft = -xScaleFactor - (turn ? 0.4 : 0.1);
            out.print(turn ? "\\node at (": "\\node[left] at (");
            out.print(DF.format(turn ? yPos : xPosLeft));
            out.print(",");
            out.print(DF.format(turn ? xPosLeft : yPos));
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