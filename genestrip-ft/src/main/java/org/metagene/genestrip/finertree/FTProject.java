package org.metagene.genestrip.finertree;

import org.metagene.genestrip.GSCommon;
import org.metagene.genestrip.GSGoalKey;
import org.metagene.genestrip.GSProject;
import org.metagene.genestrip.make.ConfigKey;

import java.io.File;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Properties;

public class FTProject extends GSProject {
    public enum FTFileType implements FileType {
        TEX(".tex");

        private final String suffix;

        private FTFileType(String suffix) {
            this.suffix = suffix;
        }

        public String getSuffix() {
            return suffix;
        }
    }

    private ConfigKey[] configKeys;

    public FTProject(GSCommon config, String name, String key, String[] fastqFiles, String csvFile, File csvDir,
                     File fastqResDir, String taxids, Properties commandLineProps, GSGoalKey forGoal,
                     String dbPath, boolean quietInit) {
        super(config, name, key, fastqFiles, csvFile, csvDir, fastqResDir, taxids, commandLineProps, forGoal, dbPath, quietInit);
    }

    @Override
    protected ConfigKey[] getConfigKeys() {
        if (configKeys == null) {
            List<ConfigKey> keys = new ArrayList<ConfigKey>(Arrays.asList(super.getConfigKeys()));
            keys.addAll(Arrays.asList(FTConfigKey.values()));
            configKeys = keys.toArray(new ConfigKey[keys.size()]);
        }
        return configKeys;
    }

    public File getTeXDir() {
        return new File(getProjectDir(), "tex");
    }

    @Override
    public File getDirForType(FileType type) {
        if (type instanceof FTFileType) {
            FTFileType ftFileType = (FTFileType) type;
            switch (ftFileType) {
                case TEX:
                    return getTeXDir();
            }
        }
        return super.getDirForType(type);
    }
}
