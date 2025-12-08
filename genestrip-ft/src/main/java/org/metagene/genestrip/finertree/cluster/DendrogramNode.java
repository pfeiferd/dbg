package org.metagene.genestrip.finertree.cluster;

public class DendrogramNode {
    public interface Visitor {
        void nextNode(DendrogramNode node);
    }

    private final int valueIndex;
    private final DendrogramNode child1;
    private final DendrogramNode child2;
    private double similarity;
    private DendrogramNode parent;

    public DendrogramNode(DendrogramNode child1, DendrogramNode child2, double similarity) {
        this.valueIndex = -1;
        this.child1 = child1;
        child1.parent = this;
        this.child2 = child2;
        child2.parent = this;
        this.similarity = similarity;
    }

    public DendrogramNode(int valueIndex, double similarity) {
        this.valueIndex = valueIndex;
        this.child1 = null;
        this.child2 = null;
        this.similarity = similarity;
    }

    public int getValueIndex() {
        return valueIndex;
    }

    public DendrogramNode getChild1() {
        return child1;
    }

    public DendrogramNode getChild2() {
        return child2;
    }

    public DendrogramNode getParent() {
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
