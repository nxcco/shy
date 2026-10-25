const img = new Image();
img.src = src;
await img.decode();
const w = img.naturalWidth || side, h = img.naturalHeight || side;
const scale = Math.min(side / w, side / h);
const canvas = document.createElement('canvas');
canvas.width = side; canvas.height = side;
canvas.getContext('2d').drawImage(img, (side - w * scale) / 2, (side - h * scale) / 2, w * scale, h * scale);
return canvas.toDataURL('image/png');
