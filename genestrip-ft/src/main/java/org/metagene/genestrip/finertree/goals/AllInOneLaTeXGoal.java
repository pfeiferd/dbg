package org.metagene.genestrip.finertree.goals;

import org.metagene.genestrip.GSProject;
import org.metagene.genestrip.finertree.FTGoalKey;
import org.metagene.genestrip.finertree.FTProject;
import org.metagene.genestrip.io.StreamProvider;
import org.metagene.genestrip.make.FileGoal;
import org.metagene.genestrip.make.Goal;

import java.io.*;
import java.nio.channels.Channels;
import java.nio.channels.ReadableByteChannel;
import java.nio.file.Files;
import java.util.Collections;
import java.util.List;

public class AllInOneLaTeXGoal extends FileGoal<GSProject> {
    private final DengrogramLaTeXGoal dengrogramLaTeXGoal;

    public AllInOneLaTeXGoal(GSProject project, DengrogramLaTeXGoal dengrogramLaTeXGoal, Goal<GSProject>... deps) {
        super(project, FTGoalKey.ALLINONE_LATEX, deps);
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
