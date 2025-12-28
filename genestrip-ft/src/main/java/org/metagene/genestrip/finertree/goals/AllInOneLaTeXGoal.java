package org.metagene.genestrip.finertree.goals;

import org.metagene.genestrip.finertree.FTGoalKey;
import org.metagene.genestrip.finertree.FTProject;
import org.metagene.genestrip.make.FileGoal;
import org.metagene.genestrip.make.Goal;

import java.io.*;
import java.nio.file.Files;
import java.util.Collections;
import java.util.List;

public class AllInOneLaTeXGoal<P extends FTProject>  extends FileGoal<P> {
    private final DengrogramLaTeXGoal<P> dengrogramLaTeXGoal;

    public AllInOneLaTeXGoal(P project, DengrogramLaTeXGoal<P> dengrogramLaTeXGoal, Goal<P>... deps) {
        super(project, FTGoalKey.ALLINONE_LATEX, append(deps, dengrogramLaTeXGoal));
        this.dengrogramLaTeXGoal = dengrogramLaTeXGoal;
    }

    @Override
    public List<File> getFiles() {
        return Collections.singletonList(getProject().getOutputFile(getKey().getName(), FTProject.FTFileType.TEX, false));
    }

    @Override
    protected void makeFile(File file) throws IOException {
        try (FileOutputStream out = new FileOutputStream(file)) {
            try (PrintStream pout = new PrintStream(out)) {
                pout.println("\\documentclass[a4paper,twoside,12pt]{article}");
                pout.println("\\usepackage{tikz}");
                pout.println("\\begin{document}");
                pout.flush();
                for (File latexFile : dengrogramLaTeXGoal.getFiles()) {
                    Files.copy(latexFile.toPath(), out);
                }
                out.flush();
                pout.println("\\end{document}");
            }
        }
    }
}
