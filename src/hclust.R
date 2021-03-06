#! /usr/bin/env Rscript

## File description -------------------------------------------------------------
## Basic hierarchical clustering approach to the antibiotics data.
##
## author: sankaran.kris@gmail.com
## date: 11/30/2017

## ---- libraries ----
library("tidyverse")
library("proxy")
library("phyloseq")
library("grid")
library("gridExtra")
library("vegan")
library("ape")
library("dendextend")
library("viridis")
library("scales")
source("data.R")

scale_colour_discrete <- function(...)
  scale_colour_brewer(..., palette="Set2")
scale_fill_discrete <- function(...)
  scale_fill_brewer(..., palette="Set2")

theme_set(theme_bw())
theme_update(
  panel.border = element_rect(size = 0.5),
  panel.grid = element_blank(),
  axis.ticks = element_blank(),
  legend.title = element_text(size = 8),
  legend.text = element_text(size = 6),
  axis.text = element_text(size = 6),
  axis.title = element_text(size = 8),
  strip.background = element_blank(),
  strip.text = element_text(size = 8),
  legend.key = element_blank()
)

figure_dir <- file.path("..", "doc", "figure")
dir.create(figure_dir)

## --- utils ----
combined_heatmap <- function(mx, fill_type = "bw") {
  p1 <- ggplot(mx) +
    geom_tile(aes(y = sample, x = as.factor(leaf_ix), fill = scaled)) +
    geom_rect(
      aes(
        ymin = -Inf, xmin = -Inf, ymax = Inf, xmax = Inf, col = label
      ),
      fill = "transparent",
      size = 0.9
    ) +
    facet_grid(ind ~ label, scales = "free", space = "free") +
    scale_x_discrete(expand = ) +
    scale_y_discrete() +
    scale_color_brewer("Taxon ", palette = "Set2") +
    theme(
      plot.margin = unit(c(0, 0, 0, 0), "null"),
      panel.border = element_blank(),
      panel.spacing.x = unit(0.1, "cm"),
      panel.spacing.y = unit(0.3, "cm"),
      legend.position = "bottom",
      axis.title = element_blank(),
      axis.text = element_blank(),
      strip.text.x = element_blank()
    )

  if (fill_type == "bw") {
    p1 <- p1 +
      scale_fill_viridis(
        "Abundance  ",
        option = "magma",
        direction = -1,
        breaks = pretty_breaks(2)
      ) +
      guides(
        fill = guide_colorbar(
          barwidth = 2,
          barheight = 0.4,
          ticks = FALSE
        )
      )
  } else if (fill_type == "gradient2"){
    p1 <- p1 +
      scale_fill_gradient2(
        "Abundance  ",
        high = "#32835f",
        low = "#833256"
      ) +
      guides(
        fill = guide_colorbar(
          barheight = 0.4,
          barwidth = 2,
          ticks = FALSE
        )
      )
  }
  p1
}

centroid_plot <- function(mx) {
  centroid_data <- mx %>%
    group_by(sample, cluster) %>%
    summarise(
      time = time[1],
      ind = ind[1],
      centroid = centroid[1],
      centroid_prob = centroid_prob[1]
    )

  p1 <- ggplot(mx) +
    geom_point(
      aes(x = time, y = scaled, col = ind), size = 0.2, alpha = 0.2
    ) +
    geom_point(
      data = centroid_data,
      aes(x = time, y = centroid), size = 0.3
    ) +
    geom_point(
      data = centroid_data,
      aes(x = time, y = centroid, col = ind), size = 0.25
    ) +
    scale_color_brewer(palette = "Set1") +
    theme(
      axis.text.x = element_blank(),
      strip.text = element_text(size = 9)
    ) +
    facet_wrap(~cluster, ncol = 10)

  p2 <- ggplot(mx) +
    geom_point(
      aes(x = time, y = present, col = ind),
      size = 0.2, alpha = 0.2,
      position = position_jitter(height = 0.2)
    ) +
    geom_point(
      data = centroid_data,
      aes(x = time, y = centroid_prob), size = 0.3
    ) +
    geom_point(
      data = centroid_data,
      aes(x = time, y = centroid_prob, col = ind), size = 0.25
    ) +
    scale_color_brewer(palette = "Set1") +
    theme(
      axis.text.x = element_blank(),
      strip.text = element_text(size = 6)
    ) +
    facet_wrap(~cluster, ncol = 8)

  list(
    "conditional" = p1,
    "presence" = p2
  )
}

## ---- data ----
download.file("https://github.com/krisrs1128/treelapse/raw/master/data/abt.rda", "../data/abt.rda")
abt <- get(load("../data/abt.rda")) %>%
  filter_taxa(function(x) { var(x) > 5 }, TRUE)

x <- t(get_taxa(abt))

## ---- pos-bin ----
## separate into conditional positive and present absence data
x_bin <- x > 0
class(x_bin) <- "numeric"

x_pos <- x
x_pos[x_pos == 0] <- NA

## ---- distances ----
D_jaccard <- dist(t(x_bin), method = "jaccard")
jaccard_tree <- hclust(D_jaccard)
plot(jaccard_tree)

x_scaled <- asinh(x) / nrow(x)

D_euclidean <- dist(t(x_scaled), method = "euclidean")
euclidean_tree <- hclust(D_euclidean)
plot(euclidean_tree)

alpha <- 0.5
D_mix <- alpha * D_jaccard + (1 - alpha) * D_euclidean
mix_tree <- hclust(D_mix)
plot(mix_tree)

## ---- heatmap-mix ----
samples <- sample_data(abt) %>%
  data.frame() %>%
  mutate(
    time_str = str_pad(time, 2, "left", "0"),
    sample = paste0(ind, time_str)
  )
taxa <- abt %>%
  tax_table %>%
  taxa_labels

mix_dendro <- reorder(as.dendrogram(mix_tree), -colMeans(x))
mx <- join_sources(x, taxa, samples, mix_dendro, h = 0.5)
sort(table(mx$cluster), decreasing = TRUE) / nrow(mx)

## save figures into list
all_plots <- list()
all_plots[["heatmap-mix"]] <- combined_heatmap(mx)
p <- centroid_plot(mx)
all_plots[["centroid-mix-conditional"]] <- p$conditional
all_plots[["centroid-mix-presence"]] <- p$presence

## ---- heatmap-extremes ----
alpha <- 0
D_mix <- alpha * D_jaccard + (1 - alpha) * D_euclidean
tree <- hclust(D_mix, method = "complete")
dendro <- reorder(as.dendrogram(tree), -colMeans(x))
mx <- join_sources(x, taxa, samples, dendro, h = 0.2)
sort(table(mx$cluster), decreasing = TRUE) / nrow(mx)
all_plots[["heatmap-euclidean"]] <- combined_heatmap(mx)
p <- centroid_plot(mx)
all_plots[["centroid-euclidean-conditional"]] <- p$conditional
all_plots[["centroid-euclidean-presence"]] <- p$presence

alpha <- 1
D_mix <- alpha * D_jaccard + (1 - alpha) * D_euclidean
tree <- hclust(D_mix)
dendro <- reorder(as.dendrogram(tree), -colMeans(x))
mx <- join_sources(x, taxa, samples, dendro, h = 0.9)
sort(table(mx$cluster), decreasing = TRUE) / nrow(mx)
all_plots[["heatmap-jaccard"]] <- combined_heatmap(mx)
p <- centroid_plot(mx)
all_plots[["centroid-jaccard-conditional"]] <- p$conditional
all_plots[["centroid-jaccard-presence"]] <- p$presence

## ---- innovations ----
diff_x <- apply(x_scaled, 2, diff)
tree <- hclust(dist(t(diff_x)))
dendro <- reorder(as.dendrogram(tree), -var(diff_x))
mx <- join_sources(diff_x, taxa, samples[-1, ], dendro, h = 0.15)
sort(table(mx$cluster), decreasing = TRUE) / nrow(mx)
all_plots[["heatmap-innovations"]] <- combined_heatmap(mx, "gradient2")
p <- centroid_plot(mx)
all_plots[["centroid-innovations-conditional"]] <- p$conditional
all_plots[["centroid-innovations-presence"]] <- p$presence

## ---- innovations-bin ----
diff_x <- apply(x_bin, 2, diff)
tree <- hclust(dist(t(diff_x), method = "Jaccard"))
dendro <- reorder(as.dendrogram(tree), -var(diff_x))
mx <- join_sources(diff_x, taxa, samples[-1, ], dendro, h = 0.985)
sort(table(mx$cluster), decreasing = TRUE) / nrow(mx)
all_plots[["heatmap-innovations-bin"]] <- combined_heatmap(mx, "gradient2")
p <- centroid_plot(mx)
all_plots[["centroid-innovations-bin-conditional"]] <- p$conditional
all_plots[["centroid-innovations-bin-presence"]] <- p$presence

## ---- pacf ----
pacfs <- t(apply(x_scaled, 2, function(x) { pacf(x, plot = FALSE)$acf[, 1, 1] }))
pacfs <- pacfs %>%
  data.frame %>%
  rownames_to_column("rsv") %>%
  gather(lag, "value", -rsv) %>%
  as_data_frame() %>%
  mutate(lag = as.integer(gsub("X", "", lag))) %>%
  left_join(taxa)

all_plots[["pacf"]] <- ggplot(pacfs) +
  geom_line(
    aes(x = lag, y = value, group = rsv, col = label),
    alpha = 0.2, size = 0.4
  ) +
  scale_fill_brewer(palette = "Set2") +
  facet_wrap(~label)

## ---- time-pairs ----
x_pairs <- x_scaled
x_offset <- rbind(x_scaled[-1, ], NA)
colnames(x_offset) <- paste0(colnames(x_offset), "_next")
x_pairs <- cbind(x_scaled, x_offset) %>%
  data.frame() %>%
  rownames_to_column("sample") %>%
  gather(rsv, "value", -sample) %>%
  mutate(
    next_val = ifelse(grepl("_next", rsv), "post", "pre"),
    rsv = gsub("_next", "", rsv)
  ) %>%
  spread(next_val, value) %>%
  as_data_frame() %>%
  left_join(samples) %>%
  left_join(taxa)

all_plots[["pacf_pairs"]] <- ggplot(x_pairs %>% filter(time >= 10, time <= 20)) +
  geom_abline(slope = 1, size = 1, alpha = 0.3) +
  geom_point(
    aes(x = pre, y = post, col = label),
    alpha = 0.2, size = 0.2
  ) +
  coord_fixed() +
  scale_color_brewer(palette = "Set2") +
  facet_grid(ind~time)

## write all the plots to file
for (i in seq_along(all_plots)) {
  cur_name <- paste0(names(all_plots)[i], ".png")
  height <- 2.5
  if (grepl("heatmap", cur_name)) {
    height <- 4
  } else if (grepl("centroid", cur_name)) {
    height <- 3
  }

  ggsave(
    file.path(figure_dir, cur_name),
    all_plots[[i]],
    dpi = 150,
    width = 4.8, height = height
  )
}
