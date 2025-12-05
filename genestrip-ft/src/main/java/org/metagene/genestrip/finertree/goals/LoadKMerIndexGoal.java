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
package org.metagene.genestrip.finertree.goals;

import me.tongfei.progressbar.ProgressBar;
import org.metagene.genestrip.GSConfigKey;
import org.metagene.genestrip.GSProject;
import org.metagene.genestrip.bloom.AbstractKMerBloomFilter;
import org.metagene.genestrip.finertree.bloom.XORKMerIndexBloomFilter;
import org.metagene.genestrip.io.StreamProvider;
import org.metagene.genestrip.io.StreamingFileResource;
import org.metagene.genestrip.io.StreamingResource;
import org.metagene.genestrip.make.FileGoal;
import org.metagene.genestrip.make.Goal;
import org.metagene.genestrip.make.GoalKey;
import org.metagene.genestrip.make.ObjectGoal;
import org.metagene.genestrip.util.progressbar.GSProgressBarCreator;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.InvalidClassException;

public class LoadKMerIndexGoal extends ObjectGoal<XORKMerIndexBloomFilter, GSProject> implements Goal.LogHeapInfo {
	public static GoalKey GOAL_KEY = new GoalKey() {
		@Override
		public String getName() {
			return "loadkmerindex";
		}
	};

	private final ObjectGoal<XORKMerIndexBloomFilter, GSProject> bloomIndex;
	private final File dbFile;

	@SafeVarargs
	public LoadKMerIndexGoal(GSProject project, ObjectGoal<XORKMerIndexBloomFilter, GSProject> bloomIndex,
                             FileGoal<GSProject> storeIndexGoal, Goal<GSProject>... dependencies) {
		super(project, GOAL_KEY, append(dependencies, bloomIndex, storeIndexGoal));
		this.bloomIndex = bloomIndex;
		this.dbFile = storeIndexGoal.getFile();
	}

	@Override
	protected void doMakeThis() {
		try {
			if (booleanConfigValue(GSConfigKey.PROGRESS_BAR) && !bloomIndex.isMade()) {
				try (StreamingResource.StreamAccess sa = new StreamingFileResource(dbFile, false).openStream()) {
					try (ProgressBar pb = GSProgressBarCreator.newGSProgressBar(getKey().getName(), sa, null)) {
						doLoadIndex(sa.getInputStream());
					}
				}
			}
			else {
				doLoadIndex(StreamProvider.getInputStreamForFile(dbFile));
			}
		} catch (IOException e) {
			throw new RuntimeException(e);
		}
	}

	protected void doLoadIndex(InputStream stream) {
		try {
			XORKMerIndexBloomFilter filter = bloomIndex.isMade() ? bloomIndex.get()
					: (XORKMerIndexBloomFilter) AbstractKMerBloomFilter.load(stream);
			set(filter);
		} catch (ClassNotFoundException e) {
			throw new RuntimeException(e);
		} catch (InvalidClassException e) {
			throw new RuntimeException("Index file version does not match genestrip library version.", e);
		} catch (IOException e) {
			throw new RuntimeException(e);
		}
	}
}
