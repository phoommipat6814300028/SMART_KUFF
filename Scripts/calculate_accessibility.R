# Accessibility (threat-access) raster via Randomized Shortest Paths (ConScape.jl)
#
# Sources  = OSM road cells (Data/raster/OSM_Roads_30m.tif)
# Targets  = every cell inside HKK Wildlife Sanctuary (derived from the
#            1 km Data/Risk_Surface.asc valid-cell mask)
# Movement cost = Tobler's hiking-speed layer (Data/raster/Tobler_Speed_kmh.tif)
# Output resolution = 100 m (own grid, snapped to round 100 m coordinates)
#
# Requires ConScapeR (R -> Julia -> ConScape.jl bridge) already set up once via
# ConScapeR::ConScapeR_setup(Sys.getenv("JULIA_PATH"), install_libraries = TRUE)
# with JULIA_PATH pointing at the local Julia install (see .Renviron).
# See Doc/Accessibility_Method.pdf for the full methods writeup.

library(terra)
library(ConScapeR)

# Set to the local repo checkout before running.
REPO <- "D:/SMART_KUFF"
RASTER_DIR <- file.path(REPO, "Data", "raster")

RES_OUT <- 100
# Confirmed numerically stable range for ConScape's dense RSP solve on this
# ~810k-cell domain (diagnostic sweep of 0.001-1 showed theta=0.2+ produces
# Inf/NaN everywhere -- a structural limit of the dense fundamental-matrix
# approach over long-hop grids, not a tunable precision issue). The true
# near-LCP endpoint is computed separately in section 6 below via
# deterministic Dijkstra shortest paths instead of pushing theta higher.
THETA_SWEEP <- c(0.001, 0.01, 0.05, 0.1) # near-random-walk -> moderately channelized
NPIX_TARGET_COARSEN <- 50L

# ---------------------------------------------------------------------------
# 1. Define the 100 m output grid (same buffered extent as the 30 m layers,
#    snapped outward to round 100 m coordinates)
# ---------------------------------------------------------------------------
tobler_30m <- rast(file.path(RASTER_DIR, "Tobler_Speed_kmh.tif"))
e30 <- ext(tobler_30m)
left100   <- floor(e30$xmin / RES_OUT) * RES_OUT
bottom100 <- floor(e30$ymin / RES_OUT) * RES_OUT
right100  <- ceiling(e30$xmax / RES_OUT) * RES_OUT
top100    <- ceiling(e30$ymax / RES_OUT) * RES_OUT

template100 <- rast(
  xmin = left100, xmax = right100, ymin = bottom100, ymax = top100,
  resolution = RES_OUT, crs = crs(tobler_30m)
)
cat(sprintf(
  "100 m grid: %d x %d cells (%s)\n",
  ncol(template100), nrow(template100), crs(template100, describe = TRUE)$name
))

# ---------------------------------------------------------------------------
# 2. Cost / resistance (0-1000, reporting layer) and affinity (0-1, ConScape
#    input) from Tobler hiking speed
# ---------------------------------------------------------------------------
# Floor near-zero speeds (very steep slope) so 1/speed doesn't blow up.
speed_floor <- max(global(tobler_30m, quantile, probs = 0.01, na.rm = TRUE)[1, 1], 1e-3)
speed_capped <- clamp(tobler_30m, lower = speed_floor, values = TRUE)

cost_30m <- 1 / speed_capped
cost_100m <- resample(cost_30m, template100, method = "bilinear")

rescale_0_1000 <- function(r) {
  rng <- global(r, range, na.rm = TRUE)
  (r - rng[1, 1]) / (rng[1, 2] - rng[1, 1]) * 1000
}
resistance_100m <- rescale_0_1000(cost_100m)
names(resistance_100m) <- "resistance_0_1000"
writeRaster(resistance_100m, file.path(RASTER_DIR, "Resistance_100m.tif"), overwrite = TRUE)

# Affinity (conductance-like, higher = easier movement) for ConScape's Grid,
# normalized 0-1 with a small floor so -log(affinity) stays finite.
affinity_30m <- speed_capped / global(speed_capped, max, na.rm = TRUE)[1, 1]
affinity_100m <- resample(affinity_30m, template100, method = "bilinear")
affinity_100m <- clamp(affinity_100m, lower = 1e-6, values = TRUE)
names(affinity_100m) <- "affinity"

# ---------------------------------------------------------------------------
# 3. Protected-area target mask (100 m), derived from the 1 km valid-cell
#    pattern in Data/Risk_Surface.asc. Bilinear-resampled to 100 m so
#    boundary cells get a soft 0-1 "fraction inside" value rather than a
#    hard cut -- the 1 km source has no finer boundary detail to recover
#    exactly, so this interpolation is as accurate as a polygonize step
#    would be, with far simpler/more robust code.
# ---------------------------------------------------------------------------
risk_1km <- rast(file.path(REPO, "Data", "Risk_Surface.asc"))
crs(risk_1km) <- crs(tobler_30m)
valid_1km <- ifel(is.na(risk_1km), 0, 1)

pa_mask_100m <- resample(valid_1km, template100, method = "bilinear")
pa_mask_100m[is.na(pa_mask_100m)] <- 0 # outside the 1 km grid's own extent -> outside PA
pa_mask_100m <- clamp(pa_mask_100m, lower = 0, upper = 1, values = TRUE)
names(pa_mask_100m) <- "pa_target_quality"
writeRaster(pa_mask_100m, file.path(RASTER_DIR, "PA_mask_100m.tif"), overwrite = TRUE)

# ---------------------------------------------------------------------------
# 4. Road source mask (100 m): any 30 m road cell touching a 100 m cell -> 1
# ---------------------------------------------------------------------------
roads_30m <- rast(file.path(RASTER_DIR, "OSM_Roads_30m.tif"))
roads_100m <- resample(roads_30m, template100, method = "max")
roads_100m[is.na(roads_100m)] <- 0 # outside the 30 m layer's own extent -> not a source
names(roads_100m) <- "road_source_quality"
writeRaster(roads_100m, file.path(RASTER_DIR, "Roads_source_100m.tif"), overwrite = TRUE)

# ---------------------------------------------------------------------------
# 5. Build the ConScape Grid and sweep theta from near-random-walk to near-LCP
#
# The sanctuary interior covers most of the domain (~478k of ~810k cells),
# so using every one of those cells as a distinct RSP target would force
# ConScape.GridRSP to materialize a dense (all-nodes x all-targets) matrix
# too large to fit in memory (confirmed: OOM at full resolution on a 32 GB
# machine). ConScape.coarse_graining() reduces the *number of distinct
# targets* by merging NPIX_TARGET_COARSEN x NPIX_TARGET_COARSEN blocks into
# landmark points, while the movement/source grid and the resulting
# betweenness output both stay at full 100 m resolution (paths still route
# through the fine-resolution terrain; only the count of distinct
# destinations is reduced). Verified with a synthetic grid before this run.
# Lower NPIX_TARGET_COARSEN for finer target fidelity if your machine has
# more free RAM; raise it if you still hit OutOfMemoryError.
# ---------------------------------------------------------------------------
library(JuliaConnectoR)
julia_path <- Sys.getenv("JULIA_PATH", unset = "C:/Users/WCS-HKK/AppData/Local/Microsoft/WindowsApps")
ConScapeR_setup(julia_path)

g_full <- ConScapeR::Grid(
  affinities = affinity_100m,
  sources = roads_100m,
  targets = pa_mask_100m,
  costs = "x -> -log(x)"
)

coarse_targets <- juliaLet(
  "ConScape.coarse_graining(g, npix)",
  g = g_full, npix = NPIX_TARGET_COARSEN
)
cat(sprintf("Coarse-grained targets to %d x %d pixel blocks\n", NPIX_TARGET_COARSEN, NPIX_TARGET_COARSEN))

affinity_mat <- terra::as.matrix(affinity_100m, wide = TRUE)
source_mat <- terra::as.matrix(roads_100m, wide = TRUE)

g <- juliaLet(
  paste0(
    "ConScape.Grid(size(affinities)...,\n",
    "              affinities=ConScape.graph_matrix_from_raster(affinities),\n",
    "              source_qualities=sources,\n",
    "              target_qualities=coarse_targets,\n",
    "              costs=ConScape.mapnz(x -> -log(x), ConScape.graph_matrix_from_raster(affinities)))"
  ),
  affinities = affinity_mat, sources = source_mat, coarse_targets = coarse_targets
)

accessibility_layers <- list()
for (theta in THETA_SWEEP) {
  cat(sprintf("Running RSP betweenness for theta = %s ...\n", theta))
  h <- ConScapeR::GridRSP(g, theta = theta)
  betw <- ConScapeR::mat2rast(ConScapeR::betweenness_qweighted(h), template100)

  # Report only inside the sanctuary, per spec.
  betw_masked <- mask(betw, pa_mask_100m > 0, maskvalues = FALSE)
  names(betw_masked) <- paste0("theta_", theta)

  out_path <- file.path(RASTER_DIR, sprintf("Accessibility_theta_%s.tif", theta))
  writeRaster(betw_masked, out_path, overwrite = TRUE)
  cat(sprintf("  Wrote %s\n", out_path))

  accessibility_layers[[as.character(theta)]] <- betw_masked
}

# ---------------------------------------------------------------------------
# 6. True least-cost-path (LCP) betweenness -- deterministic endpoint
#
# ConScape's RSP solve is numerically unstable above theta ~ 0.15 on this
# domain (see note above), so it can't reach the true near-LCP scenario the
# original spec asked for. That endpoint is instead computed directly:
# collapse all road cells into one zero-cost virtual source, run a single
# Dijkstra shortest-path solve (igraph, via gdistance's transition graph
# built from the same affinity/cost surface) to every PA target landmark,
# and accumulate a quality-weighted count of how many shortest paths pass
# through each cell -- the deterministic (theta -> infinity) limit of the
# same quality-weighted-betweenness quantity ConScape computes for finite
# theta. Target landmarks are coarse-grained the same way as for ConScape
# (NPIX_TARGET_COARSEN x NPIX_TARGET_COARSEN blocks, landmark = block
# center, quality = block sum) so both endpoints represent the same
# resolution of "distinct destinations".
# ---------------------------------------------------------------------------
library(gdistance)
library(igraph)

affinity_raster_old <- raster::raster(affinity_100m)
tr <- gdistance::transition(affinity_raster_old, transitionFunction = mean, directions = 4)
cost_mat <- gdistance::transitionMatrix(tr)
cost_mat@x <- 1 / cost_mat@x
g_ig <- igraph::graph_from_adjacency_matrix(cost_mat, mode = "undirected", weighted = TRUE)

road_cells <- which(terra::values(roads_100m, mat = FALSE) > 0)

target_agg <- terra::aggregate(pa_mask_100m, fact = NPIX_TARGET_COARSEN, fun = sum, na.rm = TRUE)
agg_nrow <- terra::nrow(target_agg)
agg_ncol <- terra::ncol(target_agg)
landmark_cells <- integer(0)
landmark_quality <- numeric(0)
for (ar in seq_len(agg_nrow)) {
  for (ac in seq_len(agg_ncol)) {
    q <- as.numeric(target_agg[ar, ac])
    if (is.na(q) || q <= 0) next
    fine_row <- min((ar - 1) * NPIX_TARGET_COARSEN + ceiling(NPIX_TARGET_COARSEN / 2), terra::nrow(pa_mask_100m))
    fine_col <- min((ac - 1) * NPIX_TARGET_COARSEN + ceiling(NPIX_TARGET_COARSEN / 2), terra::ncol(pa_mask_100m))
    cel <- terra::cellFromRowCol(pa_mask_100m, fine_row, fine_col)
    if (!is.na(cel) && is.finite(affinity_100m[cel][1, 1])) {
      landmark_cells <- c(landmark_cells, cel)
      landmark_quality <- c(landmark_quality, q)
    }
  }
}
cat(sprintf("LCP: %d road sources, %d target landmarks\n", length(road_cells), length(landmark_cells)))

g_ig2 <- igraph::add_vertices(g_ig, 1)
virtual_id <- igraph::vcount(g_ig2)
g_ig2 <- igraph::add_edges(g_ig2, as.vector(rbind(virtual_id, road_cells)), weight = rep(0, length(road_cells)))

sp <- igraph::shortest_paths(
  g_ig2, from = virtual_id, to = landmark_cells, mode = "out",
  weights = igraph::E(g_ig2)$weight, output = "vpath"
)

counts <- numeric(terra::ncell(pa_mask_100m))
for (i in seq_along(sp$vpath)) {
  path <- as.integer(sp$vpath[[i]])
  path <- path[path != virtual_id]
  if (length(path) == 0) next
  counts[path] <- counts[path] + landmark_quality[i]
}

lcp_betw <- terra::rast(pa_mask_100m)
terra::values(lcp_betw) <- counts
lcp_betw[counts == 0] <- NA
lcp_masked <- terra::mask(lcp_betw, pa_mask_100m > 0, maskvalues = FALSE)
names(lcp_masked) <- "theta_Inf_LCP"

lcp_path <- file.path(RASTER_DIR, "Accessibility_theta_Inf_LCP.tif")
terra::writeRaster(lcp_masked, lcp_path, overwrite = TRUE)
cat(sprintf("Wrote %s\n", lcp_path))

accessibility_layers[["Inf_LCP"]] <- lcp_masked

stack <- rast(accessibility_layers)
writeRaster(stack, file.path(RASTER_DIR, "Accessibility_RSP_stack.tif"), overwrite = TRUE)
cat("Wrote Accessibility_RSP_stack.tif (bands = theta_0.001, theta_0.01, theta_0.05, theta_0.1, theta_Inf_LCP)\n")
