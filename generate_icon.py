from PIL import Image, ImageDraw, ImageFont
import os

def create_calculator_icon(size=1024):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)

    # Koyu gri arka plan (iOS hesap makinesi rengi)
    for y in range(size):
        ratio = y / size
        r = int(26 + ratio * 6)
        g = int(26 + ratio * 6)
        b = int(26 + ratio * 6)
        draw.line([(0, y), (size, y)], fill=(r, g, b, 255))

    # Tuş grid boyutları
    margin = int(size * 0.09)
    btn_gap = int(size * 0.035)
    btn_rows = 5
    btn_cols = 4
    total_gap_w = btn_gap * (btn_cols - 1) + 2 * margin
    total_gap_h = btn_gap * (btn_rows - 1) + 2 * margin
    btn_w = (size - total_gap_w) // btn_cols
    btn_h = (size - total_gap_h) // btn_rows
    btn_r = btn_w // 2  # Tam yuvarlak

    # Renk şeması
    COLOR_LIGHT_GRAY = (165, 165, 165, 255)  # AC, +/-, %
    COLOR_DARK_GRAY  = (52, 52, 52, 255)     # Sayılar
    COLOR_ORANGE     = (255, 149, 0, 255)    # Operatörler

    layout = [
        ["AC", "+/-", "%",  "÷"],
        ["7",  "8",  "9",  "×"],
        ["4",  "5",  "6",  "−"],
        ["1",  "2",  "3",  "+"],
        ["0",  "",   ".",  "="],
    ]

    def draw_btn(col, row, label, color, wide=False):
        x = margin + col * (btn_w + btn_gap)
        y = margin + row * (btn_h + btn_gap)
        w = btn_w * 2 + btn_gap if wide else btn_w
        h = btn_h
        # Daire / yuvarlak dikdörtgen çiz
        draw.rounded_rectangle([x, y, x + w, y + h], radius=h // 2, fill=color)

        # Metin (basit pixel çizimi ile)
        # Renk seç
        if color == COLOR_LIGHT_GRAY:
            text_color = (0, 0, 0, 255)
        else:
            text_color = (255, 255, 255, 255)

        # Metin konumu (merkez)
        font_size = int(btn_h * 0.42)
        try:
            font = ImageFont.truetype("arial.ttf", font_size)
        except:
            font = ImageFont.load_default()

        cx = x + w // 2
        cy = y + h // 2
        bbox = draw.textbbox((0, 0), label, font=font)
        tw = bbox[2] - bbox[0]
        th = bbox[3] - bbox[1]
        draw.text((cx - tw // 2, cy - th // 2), label, font=font, fill=text_color)

    for row_idx, row in enumerate(layout):
        col_idx = 0
        skip = False
        for cell in row:
            if skip:
                skip = False
                col_idx += 1
                continue
            if row_idx == 4 and cell == "0":
                draw_btn(col_idx, row_idx, "0", COLOR_DARK_GRAY, wide=True)
                col_idx += 2
                skip = True
                continue
            if cell == "":
                col_idx += 1
                continue
            if cell in ["AC", "+/-", "%"]:
                color = COLOR_LIGHT_GRAY
            elif cell in ["÷", "×", "−", "+", "="]:
                color = COLOR_ORANGE
            else:
                color = COLOR_DARK_GRAY
            draw_btn(col_idx, row_idx, cell, color)
            col_idx += 1

    # Kaydet
    out_dir = r"C:\Users\Casper\Downloads\1\AppVault\Assets"
    os.makedirs(out_dir, exist_ok=True)
    img.save(os.path.join(out_dir, "AppIcon1024.png"))
    img.resize((180, 180), Image.Resampling.LANCZOS).save(os.path.join(out_dir, "AppIcon60x60@3x.png"))
    img.resize((120, 120), Image.Resampling.LANCZOS).save(os.path.join(out_dir, "AppIcon60x60@2x.png"))
    print("[+] Hesap makinesi ikonu basariyla olusturuldu!")

if __name__ == "__main__":
    create_calculator_icon()
