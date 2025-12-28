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

import org.metagene.genestrip.goals.MDDescription;
import org.metagene.genestrip.make.GoalKey;

import java.io.PrintStream;
import java.lang.annotation.Annotation;

public enum FTGoalKey implements GoalKey {
    FTSETUP("ftsetup"),
    DENDROGRAM("dendrogram"),
    DENDRO_LATEX("dendrolatex", true),
    KMER_INDEX_BLOOM("kmerindexbloom"),
    INTERSECT_COUNT("intersectcount"),
    INTERSECT_CSV("intersectcsv", true),
    LOAD_KMER_INDEX("loadkmerindex"),
    STORE_KMER_INDEX("storekmerindex"),
    UPDATE_STORE_GOAL("updatestore"),
    FTDB("ftdb", true),
    FTDBINFO("ftdbinfo", true),
    LOAD_FTDB("loadftdb"),
    ALLINONE_LATEX("allinonelatex", true);

    private final boolean forUser;
    private final String name;

    private FTGoalKey(String name) {
        this(name, false);
    }

    private FTGoalKey(String name, boolean forUser) {
        this.name = name;
        this.forUser = forUser;
    }

    public boolean isForUser() {
        return forUser;
    }

    public String getName() {
        return name;
    }

    public static void printGoalInfo(PrintStream ps) {
        ps.print('|');
        ps.print("Name");
        ps.print('|');
        ps.print("User Goal");
        ps.print('|');
        ps.print("Description");
        ps.print('|');
        ps.println();

        ps.print('|');
        ps.print('-');
        ps.print('|');
        ps.print('-');
        ps.print('|');
        ps.print('-');
        ps.print('|');
        ps.println();

        for (FTGoalKey goalKey : FTGoalKey.values()) {
            ps.print('|');
            ps.print('`');
            ps.print(goalKey.getName());
            ps.print('`');
            ps.print('|');
            ps.print(goalKey.isForUser() ? "X" : "");
            ps.print('|');
            Annotation[] annotations;
            try {
                annotations = FTGoalKey.class.getField(goalKey.name()).getAnnotations();
            } catch (NoSuchFieldException e) {
                throw new RuntimeException(e);
            } catch (SecurityException e) {
                throw new RuntimeException(e);
            }
            for (Annotation annotation : annotations) {
                if (annotation instanceof MDDescription) {
                    ps.print(((MDDescription) annotation).value());
                    break;
                }
            }
            ps.print('|');
            ps.println();
        }
    }
}
