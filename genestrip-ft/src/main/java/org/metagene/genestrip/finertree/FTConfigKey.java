/*
 * 
 * “Commons Clause” License Condition v1.0
 * 
 * The Software is provided to you by the Licensor under the License, 
 * as defined below, subject to the following condition.
 * 
 * Without limiting other conditions in the License, the grant of rights under the License 
 * will not include, and the License does not grant to you, the right to Sell the Software.
 * 
 * For purposes of the foregoing, “Sell” means practicing any or all of the rights granted 
 * to you under the License to provide to third parties, for a fee or other consideration 
 * (including without limitation fees for hosting or consulting/ support services related to 
 * the Software), a product or service whose value derives, entirely or substantially, from the 
 * functionality of the Software. Any license notice or attribution required by the License 
 * must also include this Commons Clause License Condition notice.
 * 
 * Software: genestrip-ft
 * 
 * License: Apache 2.0
 * 
 * Licensor: Daniel Pfeifer (daniel.pfeifer@progotec.de)
 * 
 */
package org.metagene.genestrip.finertree;

import org.metagene.genestrip.GSGoalKey;
import org.metagene.genestrip.finertree.cluster.SimpleAggloClustering;
import org.metagene.genestrip.make.ConfigKey;
import org.metagene.genestrip.make.ConfigParamInfo;
import org.metagene.genestrip.make.GoalKey;
import org.metagene.genestrip.tax.Rank;

import java.util.*;

public enum FTConfigKey implements ConfigKey {
    REFINEMENT_RANKS("refinementRanks", new ConfigParamInfo.ListConfigParamInfo<Rank>(Collections.unmodifiableList(Arrays.asList(Rank.GENUS, Rank.SPECIES_GROUP))) {
                @Override
                protected List<Rank> fromString(String qs) {
                    List<Rank> res = new ArrayList<Rank>();
                    if (qs != null) {
                        StringTokenizer tokenizer = new StringTokenizer(qs, ",;");
                        while (tokenizer.hasMoreTokens()) {
                            Rank r = Rank.valueOf(tokenizer.nextToken().trim());
                            if (r != null) {
                                res.add(r);
                            }
                        }
                    }
                    return res;
                }
            }, FTGoalKey.KMER_INDEX_BLOOM, FTGoalKey.DENDRO_LATEX, FTGoalKey.INTERSECT_COUNT, FTGoalKey.INTERSECT_CSV),
    CLUSTER_METHOD("clusterMethod", new MethodConfigParamInfo(SimpleAggloClustering.Method.SINGLE_LINKAGE), FTGoalKey.DENDROGRAM),
    WITH_CHILD_COUNTS("withChildCounts", new ConfigParamInfo.BooleanConfigParamInfo(false), FTGoalKey.INTERSECT_COUNT),
    TURN_LATEX("turnLatex", new ConfigParamInfo.BooleanConfigParamInfo(true), FTGoalKey.DENDRO_LATEX),
    X_FACTOR_LATEX("xFactorLatex",new ConfigParamInfo.DoubleConfigParamInfo(0,Double.MAX_VALUE, 1), FTGoalKey.DENDRO_LATEX),
    Y_FACTOR_LATEX("yFactorLatex", new ConfigParamInfo.DoubleConfigParamInfo(0,Double.MAX_VALUE, 8), FTGoalKey.DENDRO_LATEX),
    FT_BLOOM_FILTER_FPP("ftBloomFilterFpp", new ConfigParamInfo.DoubleConfigParamInfo(0, 1, 0.001d), true, FTGoalKey.KMER_INDEX_BLOOM);


    private final String name;
    private final ConfigParamInfo<?> param;
    private final boolean internal;
    private final FTGoalKey[] forGoals;

    FTConfigKey(String name, ConfigParamInfo<?> param, FTGoalKey... forGoals) {
        this(name, param, false, forGoals);
    }

    FTConfigKey(String name, ConfigParamInfo<?> param, boolean internal, FTGoalKey... forGoals) {
        this.name = name;
        this.param = param;
        this.internal = internal;
        this.forGoals = forGoals;
    }

    public boolean isInternal() {
        return internal;
    }

    @Override
    public String getName() {
        return name;
    }

    public ConfigParamInfo<?> getInfo() {
        return param;
    }

    public boolean isForGoal(GoalKey forGoal) {
        if (forGoal == null) {
            return true;
        }
        for (GoalKey id : forGoals) {
            if (forGoal.equals(id)) {
                return true;
            }
        }
        return false;
    }

    @Override
    public String toString() {
        return getName();
    }

    public static class MethodConfigParamInfo extends ConfigParamInfo<SimpleAggloClustering.Method> {
        public MethodConfigParamInfo(SimpleAggloClustering.Method defaultValue) {
            super(defaultValue);
        }

        @Override
        public boolean isValueInRange(Object o) {
            return o == null || o instanceof SimpleAggloClustering.Method;
        }

        @Override
        protected SimpleAggloClustering.Method fromString(String s) {
            return SimpleAggloClustering.Method.valueOf(s);
        }

        @Override
        public String getMDRangeDescriptor() {
            StringBuilder builder = new StringBuilder();
            SimpleAggloClustering.Method[] methods = SimpleAggloClustering.Method.values();
            for (int i = 0; i < methods.length; i++) {
                if (i > 0) {
                    builder.append(", ");
                }
                builder.append('`');
                builder.append(methods[i].name());
                builder.append('`');
            }
            return builder.toString();
        }

        @Override
        public String getTypeDescriptor() {
            return "nominal";
        }
    }
}
