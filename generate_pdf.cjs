const { PDFDocument, rgb, StandardFonts } = require('pdf-lib');
const fs = require('fs');
const path = require('path');

async function createInvoice() {
    const pdfDoc = await PDFDocument.create();
    const page = pdfDoc.addPage([595.28, 841.89]); // A4
    const { width, height } = page.getSize();
    const font = await pdfDoc.embedFont(StandardFonts.Helvetica);
    const boldFont = await pdfDoc.embedFont(StandardFonts.HelveticaBold);

    const drawText = (text, x, y, size = 10, fontRef = font) => {
        page.drawText(text, { x, y, size, font: fontRef, color: rgb(0, 0, 0) });
    };

    // Header - Prodavac
    let y = height - 50;
    drawText('PR Limo Servis Gavra 013 (Bojan Gavrilovic)', 50, y, 12, boldFont);
    y -= 15;
    drawText('Mihajla Pupina 74, 26340 Bela Crkva', 50, y);
    y -= 15;
    drawText('PIB: 102853497 | MB: 55572178', 50, y);
    y -= 15;
    drawText('Ziro racun: 340-11436537-92', 50, y);

    // Divider
    y -= 25;
    page.drawLine({ start: { x: 50, y }, end: { x: 545, y }, thickness: 1, color: rgb(0, 0, 0) });

    // Kupac
    y -= 30;
    drawText('KUPAC:', 50, y, 10, boldFont);
    y -= 15;
    drawText('Sportsko drustvo Radnicki Kovin', 50, y, 12, boldFont);
    y -= 15;
    drawText('Cara Lazara 85, Kovin', 50, y);
    y -= 15;
    drawText('PIB: 105096547', 50, y);

    // Naslov racuna
    y -= 50;
    drawText('RACUN br. 1/2026', 220, y, 18, boldFont);
    y -= 25;
    drawText('Datum prometa: 29.03.2026.', 50, y);
    drawText('Mesto izdavanja: Bela Crkva', 400, y);

    // Tabela / Stavke
    y -= 40;
    page.drawRectangle({ x: 50, y: y - 5, width: 495, height: 20, color: rgb(0.9, 0.9, 0.9) });
    drawText('Opis usluge', 60, y, 10, boldFont);
    drawText('Iznos', 480, y, 10, boldFont);

    const stavke = [
        'Prevoz putnika na relacijama:',
        ' - Gaj - Cardak - Gaj',
        ' - Plocica - Cardak - Plocica',
        ' - Deliblato - Cardak - Deliblato',
        ' - Dubovac - Cardak - Dubovac',
        ' - Bavaniste - Cardak - Bavaniste'
    ];

    y -= 25;
    stavke.forEach(line => {
        drawText(line, 60, y);
        y -= 15;
    });

    // Ukupno
    y -= 30;
    const lineY = y + 15;
    page.drawLine({ start: { x: 350, y: lineY }, end: { x: 545, y: lineY }, thickness: 1, color: rgb(0, 0, 0) });
    drawText('UKUPNO ZA UPLATU:', 350, lineY - 15, 12, boldFont);
    drawText('48.600,00 RSD', 460, lineY + 5, 12, boldFont);

    // Footer / Napomene
    y -= 80;
    drawText('Napomene:', 50, y, 9, boldFont);
    y -= 15;
    drawText('Oslobodjeno placanja PDV-a po Clanu 33. Zakona o porezu na dodatu vrednost.', 50, y, 9);
    y -= 12;
    drawText('Racun je punovazan bez pecata i potpisa u skladu sa Clanom 9. Zakona o racunovodstvu.', 50, y, 9);
    y -= 12;
    drawText('Uplata na ziro racun: 340-11436537-92, poziv na broj: 1/2026', 50, y, 9);    // Potpis
    y -= 50;
    drawText('________________________', 400, y);
    y -= 15;
    drawText('Bojan Gavrilovic, vlasnik', 400, y, 9);

    const pdfBytes = await pdfDoc.save();
    const dir = path.join('c:', 'Users', 'Bojan', 'gavra_android', 'distribution');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'Racun_1_2026_Radnicki.pdf'), pdfBytes);
    console.log('PDF uspesno generisan u distribution folderu!');
}

createInvoice().catch(err => console.error(err));
