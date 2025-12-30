package org.metagene.genestrip.finertree.goals;

import org.metagene.genestrip.finertree.FTConfigKey;
import org.metagene.genestrip.finertree.FTGoalKey;
import org.metagene.genestrip.finertree.FTProject;
import org.metagene.genestrip.make.FileGoal;
import org.metagene.genestrip.make.Goal;

import java.io.*;
import java.nio.file.Files;
import java.util.*;

public class AllInOneLaTeXGoal<P extends FTProject>  extends FileGoal<P> {
    private final DengrogramLaTeXGoal<P> dengrogramLaTeXGoal;
    private final Map<File, List<File>> outToInFiles;

    public AllInOneLaTeXGoal(P project, DengrogramLaTeXGoal<P> dengrogramLaTeXGoal, Goal<P>... deps) {
        super(project, FTGoalKey.ALLINONE_LATEX, append(deps, dengrogramLaTeXGoal));
        this.dengrogramLaTeXGoal = dengrogramLaTeXGoal;
        this.outToInFiles = new HashMap<>();
    }

    @Override
    public List<File> getFiles() {
        List<File> files = dengrogramLaTeXGoal.getFiles();
        int total = files.size();
        int stepSize = intConfigValue(FTConfigKey.ALLINONE_CHUNK_SIZE);
        List<File> res = new ArrayList<>();
        for (int i = 0; i < total; i += stepSize) {
            res.add(getProject().getOutputFile(getKey().getName(), Integer.toString(i), null, FTProject.FTFileType.TEX, false));
            List<File> inFiles = new ArrayList<>();
            for (int j = i; j < stepSize && j < total; j++) {
                inFiles.add(files.get(j));
            }
        }
        return res;
    }

    @Override
    protected void makeFile(File file) throws IOException {
        try (FileOutputStream out = new FileOutputStream(file)) {
            try (PrintStream pout = new PrintStream(out)) {
                pout.println("\\documentclass[border=0]{standalone}");
                pout.println("\\usepackage{tikz}");
                pout.println("\\begin{document}");
                pout.println("\\begin{minipage}{21cm}");
                pout.flush();
                for (File latexFile : outToInFiles.get(file)) {
                    Files.copy(latexFile.toPath(), out);
                }
                out.flush();
                pout.println("\\end{minipage}");
                pout.println("\\end{document}");
            }
        }
    }
}
