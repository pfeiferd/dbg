package org.metagene.genestrip.finertree.cluster;

import java.io.PrintStream;
import java.io.PrintWriter;

public class DendroGramNode {
    public interface Visitor {
        void nextNode(DendroGramNode node);
    }

    private final int valueIndex;
    private final DendroGramNode child1;
    private final DendroGramNode child2;
    private double similarity;
    private DendroGramNode parent;

    public DendroGramNode(DendroGramNode child1, DendroGramNode child2, double similarity) {
        this.valueIndex = -1;
        this.child1 = child1;
        child1.parent = this;
        this.child2 = child2;
        child2.parent = this;
        this.similarity = similarity;
    }

    public DendroGramNode(int valueIndex, double similarity) {
        this.valueIndex = valueIndex;
        this.child1 = null;
        this.child2 = null;
        this.similarity = similarity;
    }

    public int getValueIndex() {
        return valueIndex;
    }

    public DendroGramNode getChild1() {
        return child1;
    }

    public DendroGramNode getChild2() {
        return child2;
    }

    public DendroGramNode getParent() {
        return parent;
    }

    public double getSimilarity() {
        return similarity;
    }

    public void visit(Visitor visitor) {
        visitor.nextNode(this);
        if (valueIndex != - 1) {
            child1.visit(visitor);
            child2.visit(visitor);
        }
    }
}
