//! I saw this idea couple weeks back, hopefully
//! I'm remembering it correctly.
//!
//! Basically what you want to do is read in a file,
//! Construct a windowing iterator over two bytes
//! at a time, and then you use look up one byte
//! as the row of the image and you use the other byte
//! as a col. Add one to the value addresed by these to indexes.
//! in the image.
//!
//! You should generate an image, and different file formats
//! should have different appearances, which you could train a
//! CNN on.
//!
//! The image should be black to begin with.
//! The image should be normalized to [0, 1], and
//! then displayed by rendering

use eframe::Theme;
use egui::load::SizedTexture;
use egui::{Color32, ColorImage, Layout, TextureHandle, TextureOptions};
use image::ImageBuffer;
use image::Luma;
use std::io::{BufReader, Read};
use std::sync::Arc;

use fs_err as fs;
use itertools::Itertools;

fn read_file<P: AsRef<std::path::Path>>(
    path: P,
) -> std::io::Result<impl Iterator<Item = (u8, u8)>> {
    let open = fs::File::open(path.as_ref()).map(BufReader::new)?;

    Ok(open
        .bytes()
        .flat_map(std::convert::identity)
        .tuple_windows())
}

#[derive(Default)]
struct EguiBrowser {
    selected_texture: Option<usize>,
    file_names: Vec<String>,
    active_textures: Vec<TextureHandle>,
}

impl EguiBrowser {
    fn new(cc: &eframe::CreationContext) -> Self {
        egui_extras::install_image_loaders(&cc.egui_ctx);
        Self::default()
    }
}

impl eframe::App for EguiBrowser {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        egui::SidePanel::left("#left-panel")
            .resizable(true)
            .default_width(400.0)
            .show(ctx, |ui: &mut egui::Ui| {
                egui::ScrollArea::vertical()
                    .max_height(72.0)
                    .show(ui, |ui| {
                        let width = ui.available_width();
                        for (i, file_name) in self.file_names.iter().enumerate() {
                            let selectable = ui.add_sized(
                                [width, 20.0],
                                egui::SelectableLabel::new(
                                    self.selected_texture.map(|idx| idx == i).unwrap_or(false),
                                    file_name,
                                ),
                            );
                            if selectable.clicked() {
                                self.selected_texture = Some(i);
                            }
                        }
                    });

                if ui.button("Open File").clicked() {
                    if let Some(path) = rfd::FileDialog::new().pick_file() {
                        let bytes = load_input(&path).expect("failed to read file");

                        self.file_names.push(
                            path.file_name()
                                .expect("not a valid filename")
                                .to_string_lossy()
                                .into_owned(),
                        );
                        self.active_textures.push(
                            ui.ctx().load_texture(
                                "#view-image".to_owned(),
                                egui::ImageData::Color(Arc::new(ColorImage {
                                    size: [256, 256],
                                    pixels: bytes
                                        .map(|b| (b * 255.0) as u8)
                                        .map(Color32::from_gray)
                                        .as_slice()
                                        .to_vec(),
                                })),
                                TextureOptions::LINEAR,
                            ),
                        );
                        self.selected_texture = Some(self.active_textures.len() - 1);
                    }
                }
            });
        egui::CentralPanel::default().show(ctx, |ui: &mut egui::Ui| {
            ui.centered_and_justified(|ui| match &self.selected_texture {
                Some(idx) => {
                    ui.add(
                        egui::Image::from_texture(SizedTexture {
                            id: self.active_textures[*idx].id(),
                            size: self.active_textures[*idx].size_vec2(),
                        })
                        .rounding(5.0)
                        .shrink_to_fit(),
                    );
                }
                None => {
                    ui.label("Click open to load an image");
                }
            });
        });
    }
}
fn main() -> std::io::Result<()> {
    let native_options = eframe::NativeOptions {
        follow_system_theme: false,
        default_theme: Theme::Dark,
        ..Default::default()
    };
    eframe::run_native(
        "Bytes View",
        native_options,
        Box::new(|cc| Box::new(EguiBrowser::new(cc))),
    )
    .unwrap();
    let input = std::env::args_os()
        .nth(1)
        .expect("[USAGE]: binary-guess <FILE-PATH>");

    let input = std::path::PathBuf::from(input);

    let bytes = load_input(&input)?;

    let img: ImageBuffer<Luma<u8>, Vec<u8>> = ImageBuffer::from_raw(
        256,
        256,
        bytes.map(|byte| (byte * 255.0) as u8).as_slice().to_vec(),
    )
    .unwrap();

    img.save(input.with_extension("png").file_name().unwrap())
        .unwrap();

    Ok(())
}

fn load_input<P: AsRef<std::path::Path>>(input: &P) -> std::io::Result<[f64; 256 * 256]> {
    let mut bytes: [f64; 256 * 256] = [0.0; 256 * 256];
    let contents = read_file(input)?;
    for (row, col) in contents {
        bytes[row as usize + col as usize * 256] += 1.0;
    }
    let mut bytes = bytes.map(|byte| byte.log2());
    let max = bytes
        .iter()
        .copied()
        .reduce(|highest, test| if highest > test { highest } else { test })
        .unwrap();
    for byte in bytes.iter_mut() {
        *byte /= max;
    }

    Ok(bytes)
}
