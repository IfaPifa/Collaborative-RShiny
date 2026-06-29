package com.example.shinyswarm.state;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Shared logic for restoring a saved checkpoint.
 *
 * A saved checkpoint is a RESULT message captured from the {@code output}
 * topic: it already contains computed results, not a {@code command}. The R
 * backends only act on command messages ({@code START_SIMULATION},
 * {@code TRAIN_MODEL}, ...) and skip everything else, so a restored checkpoint
 * must be published straight to {@code output} for the frontends to render it,
 * rather than sent through an {@code input} topic where it would be ignored.
 *
 * For the Climate Anomaly app, the checkpoint embeds the dataset; it is written
 * back to the shared volume so the Shiny app can read it from disk, preserving
 * the shared-volume pattern.
 */
public final class StateRestoreSupport {

    private StateRestoreSupport() {}

    /**
     * If the payload is a Climate checkpoint with an embedded dataset, write the
     * dataset back to the shared volume as CSV and remove it from the payload
     * (the Shiny app reads from disk, not from JSON).
     */
    @SuppressWarnings("unchecked")
    public static void restoreClimateFile(Map<String, Object> payload) {
        try {
            String action = (String) payload.get("action");
            String file = (String) payload.get("file");
            Object dataset = payload.get("dataset");

            if (!"CLIMATE_READY".equals(action) || file == null || dataset == null) {
                return;
            }

            List<Map<String, Object>> rows = (List<Map<String, Object>>) dataset;
            if (rows.isEmpty()) return;

            StringBuilder csv = new StringBuilder();
            List<String> headers = new ArrayList<>(rows.get(0).keySet());
            csv.append(String.join(",", headers)).append("\n");

            for (Map<String, Object> row : rows) {
                List<String> values = new ArrayList<>();
                for (String h : headers) {
                    Object v = row.get(h);
                    String val = v != null ? v.toString() : "";
                    if (val.contains(",")) val = "\"" + val + "\"";
                    values.add(val);
                }
                csv.append(String.join(",", values)).append("\n");
            }

            Path csvPath = Paths.get("/app/shared_data", file);
            Files.writeString(csvPath, csv.toString());

            payload.remove("dataset");
        } catch (Exception e) {
            System.err.println("Climate file restore failed: " + e.getMessage());
        }
    }
}
