// One sheet for every entry: expense, income, contract, warranty, document. Editing uses the same sheet.
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct AddSheet: View {
    @State var mode: AddMode
    var contract: Contract?
    var product: Product?
    var money: Money?

    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    // money
    @State private var amount = ""
    @State private var date = Date.now
    @State private var category = "market"
    @State private var party = ""
    @State private var linked = ""
    @State private var method = ""
    @State private var note = ""
    // contract
    @State private var provider = ""
    @State private var kind = "mobile"
    @State private var holder = "me"
    @State private var label = ""
    @State private var yearly = false
    @State private var billDay = 1
    @State private var hasBillDay = true
    @State private var start = Date.now
    @State private var hasStart = false
    @State private var hasEnd = false
    @State private var end = Day.cal.date(byAdding: .month, value: 12, to: .now)!
    @State private var exitFee = ""
    @State private var priceClause = ""
    @State private var terms = ""
    @State private var active = true
    // product
    @State private var name = ""
    @State private var seller = ""
    @State private var warrantyEnd = Day.cal.date(byAdding: .year, value: 2, to: .now)!
    // document
    @State private var picking = false
    @State private var photo: PhotosPickerItem?
    @State private var docNote = ""
    @State private var error = ""

    private var editing: Bool { contract != nil || product != nil || money != nil }

    var body: some View {
        NavigationStack {
            Form {
                if !editing {
                    Picker("Tür", selection: $mode) { ForEach(AddMode.allCases) { Text($0.name).tag($0) } }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                switch mode {
                case .expense, .income: moneyForm
                case .contract: contractForm
                case .product: productForm
                case .document: documentForm
                }
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(Color.attention) }
            }
            .navigationTitle(editing ? "\(mode.name) düzenle" : "\(mode.name) ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                if mode != .document { ToolbarItem(placement: .confirmationAction) { Button("Kaydet") { save() }.fontWeight(.semibold) } }
            }
            .onAppear(perform: fill)
            .onChange(of: mode) { _, m in
                error = ""
                if m == .income && !Catalog.income.contains(where: { $0.id == category }) { category = "maaş" }
                if m == .expense && !Catalog.expense.contains(where: { $0.id == category }) { category = "market" }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: forms

    @ViewBuilder private var moneyForm: some View {
        Section {
            HStack {
                TextField("0", text: $amount).keyboardType(.decimalPad).font(.system(size: 40, weight: .semibold, design: .rounded))
                    .onChange(of: amount) { _, _ in error = "" }
                Text("₺").font(.title).foregroundStyle(.secondary)
            }
            DatePicker("Tarih", selection: $date, displayedComponents: .date)
        }
        Section("Kategori") {
            let list = mode == .income ? Catalog.income : Catalog.expense
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(list) { c in
                        Button { category = c.id } label: {
                            VStack(spacing: 4) {
                                Image(systemName: c.symbol).font(.title3).foregroundStyle(category == c.id ? .white : c.color)
                                    .frame(width: 46, height: 46)
                                    .background(category == c.id ? AnyShapeStyle(c.color.gradient) : AnyShapeStyle(c.color.opacity(0.14)), in: Circle())
                                Text(c.name).font(.caption2).lineLimit(1).frame(width: 66)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(c.name)
                        .accessibilityAddTraits(category == c.id ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
        Section {
            TextField(mode == .income ? "Kimden (işveren, müşteri)" : "Kime (market, kurum)", text: $party)
            if mode == .expense && !store.contracts.isEmpty {
                Picker("Sözleşme", selection: $linked) {
                    Text("Yok").tag("")
                    ForEach(store.contracts) { c in Text("\(c.provider.ifEmpty(Catalog.kind(c.kind).name)) · \(store.personName(c.holder))").tag(c.id) }
                }
                .onChange(of: linked) { _, id in
                    if let c = store.contracts.first(where: { $0.id == id }) {
                        category = Catalog.kind(c.kind).category
                        if party.isEmpty { party = c.provider }
                        if amount.isEmpty, let a = c.amount { amount = TL.text(a).replacingOccurrences(of: " ₺", with: "") }
                    }
                }
            }
            TextField("Ödeme yolu (ör. kart …1234, nakit)", text: $method)
            TextField("Not", text: $note, axis: .vertical)
        } footer: { Text("Kart numarasının tamamını yazma: uzun rakam dizisi son 4 hanesine indirilir.") }
    }

    @ViewBuilder private var contractForm: some View {
        Section {
            TextField("Sağlayıcı (operatör, kurum, ev sahibi)", text: $provider)
            Picker("Tür", selection: $kind) { ForEach(Catalog.kinds, id: \.id) { k in Label(k.name, systemImage: k.symbol).tag(k.id) } }
            Picker("Kimin adına", selection: $holder) { ForEach(store.household) { Text($0.name).tag($0.id) } }
            TextField("Etiket (ör. hat …1234, ev fiber)", text: $label)
        }
        Section("Ücret") {
            HStack {
                TextField("Tutar", text: $amount).keyboardType(.decimalPad).font(.title2.weight(.semibold))
                Text("₺").foregroundStyle(.secondary)
                Picker("", selection: $yearly) { Text("ayda").tag(false); Text("yılda").tag(true) }.pickerStyle(.segmented).frame(width: 130)
            }
            if !yearly {
                Toggle("Fatura günü belli", isOn: $hasBillDay)
                if hasBillDay { Stepper("Her ayın \(billDay)'i", value: $billDay, in: 1...31) }
            }
            TextField("Ödeme yolu (ör. kart …4321 otomatik)", text: $method)
        }
        Section("Taahhüt") {
            Toggle("Başlangıç tarihi", isOn: $hasStart)
            if hasStart || yearly { DatePicker("Başladı", selection: $start, displayedComponents: .date) }
            Toggle("Taahhüt var", isOn: $hasEnd)
            if hasEnd {
                DatePicker("Bitiyor", selection: $end, displayedComponents: .date)
                TextField("Cayma bedeli (ör. kalan ay × indirim)", text: $exitFee)
            }
            TextField("Fiyat şartı (ör. 12 ay sabit, sonra liste fiyatı)", text: $priceClause, axis: .vertical)
        }
        Section {
            TextField("Her satıra bir madde", text: $terms, axis: .vertical).lineLimit(3...8)
        } header: { Text("Ana maddeler") } footer: { Text("Sözleşmede seni bağlayan en önemli 3–6 madde. Belge eklersen Claude da çıkarır.") }
        Section {
            Toggle("Aktif", isOn: $active)
            TextField("Not", text: $note, axis: .vertical)
        }
    }

    @ViewBuilder private var productForm: some View {
        Section {
            TextField("Ürün (ör. buzdolabı)", text: $name)
            DatePicker("Alış", selection: $start, displayedComponents: .date)
                .onChange(of: start) { _, s in if product == nil { warrantyEnd = Day.cal.date(byAdding: .year, value: 2, to: s)! } }
            DatePicker("Garanti bitişi", selection: $warrantyEnd, displayedComponents: .date)
        } footer: { Text("Türkiye'de yeni ürünlerde yasal garanti çoğu zaman 2 yıldır; belgedeki tarihi gir.") }
        Section {
            HStack { TextField("Fiyat", text: $amount).keyboardType(.decimalPad); Text("₺").foregroundStyle(.secondary) }
            TextField("Satıcı", text: $seller)
            TextField("Not (seri no, servis telefonu)", text: $note, axis: .vertical)
        }
    }

    @ViewBuilder private var documentForm: some View {
        Section {
            Button { picking = true } label: { Label("Dosya seç (PDF, CSV, görsel)", systemImage: "doc.badge.plus") }
            PhotosPicker(selection: $photo, matching: .images) { Label("Fotoğraflardan seç", systemImage: "photo") }
        } footer: {
            Text("Belge vault'a gider. Mac'te Claude'a \"FBS'yi düzenle\" dediğinde okunur: sözleşmeyse ana maddeleri, faturaysa ödeme, ekstreyse bütün hareketler deftere işlenir.")
        }
        if !docNote.isEmpty { Text(docNote).foregroundStyle(Color.money) }
        Color.clear.frame(height: 0)
            .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf, .image, .commaSeparatedText, .plainText], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                Task { for u in urls { await store.addDocument(from: u, title: "") }; docNote = "\(urls.count) belge eklendi." }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) { await store.addDocument(data: data, title: "Fotoğraf", ext: "jpg"); docNote = "Fotoğraf eklendi." }
                    photo = nil
                }
            }
    }

    // MARK: fill and save

    private func fill() {
        if let m = money {
            amount = TL.text(m.amount).replacingOccurrences(of: " ₺", with: ""); date = Day.parse(m.date) ?? .now
            category = m.category ?? "diğer"; party = m.party ?? ""; linked = m.contract ?? ""; method = m.method ?? ""; note = m.note ?? ""
        } else if let c = contract {
            provider = c.provider; kind = c.kind; holder = c.holder ?? "me"; label = c.label ?? ""; yearly = c.yearly
            amount = c.amount.map { TL.text($0).replacingOccurrences(of: " ₺", with: "") } ?? ""
            hasBillDay = c.billDay != nil; billDay = c.billDay ?? 1; method = c.payMethod ?? ""
            hasStart = c.start != nil; start = Day.parse(c.start) ?? .now
            hasEnd = c.commitmentEnd != nil; end = Day.parse(c.commitmentEnd) ?? end
            exitFee = c.exitFee ?? ""; priceClause = c.priceClause ?? ""; terms = (c.keyTerms ?? []).joined(separator: "\n")
            active = c.isActive; note = c.note ?? ""
        } else if let p = product {
            name = p.name; start = Day.parse(p.bought) ?? .now; warrantyEnd = Day.parse(p.warrantyEnd) ?? warrantyEnd
            amount = p.price.map { TL.text($0).replacingOccurrences(of: " ₺", with: "") } ?? ""; seller = p.seller ?? ""; note = p.note ?? ""
        } else {
            holder = store.household.first?.id ?? "me"
            if mode == .income { category = "maaş" }
        }
    }

    private func clean(_ s: String) -> String? { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }

    private func save() {
        switch mode {
        case .expense, .income:
            guard let a = TL.parse(amount), a > 0 else { error = "Tutarı yaz (ör. 450 ya da 1.250,50)."; return }
            store.save(Money(id: money?.id ?? Store.newID(mode == .income ? "in" : "out"), date: Day.key(date), kind: mode == .income ? "input" : "output",
                             category: category, amount: a, currency: "TRY", party: clean(party), contract: mode == .expense ? clean(linked) : nil,
                             method: clean(method), note: clean(note), source: "telefon", created: money?.created))
        case .contract:
            guard clean(provider) != nil || kind != "other" else { error = "Sağlayıcıyı yaz."; return }
            let a = TL.parse(amount)
            if !amount.isEmpty && a == nil { error = "Tutar okunamadı (ör. 450 ya da 699,90)."; return }
            if hasEnd && hasStart && end <= start { error = "Taahhüt bitişi başlangıçtan sonra olmalı."; return }
            let keyTerms = terms.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            store.save(Contract(id: contract?.id ?? Store.newID("ct"), provider: clean(provider) ?? "", kind: kind, holder: holder, label: clean(label),
                                status: active ? "active" : "ended", start: (hasStart || yearly) ? Day.key(start) : nil, commitmentEnd: hasEnd ? Day.key(end) : nil,
                                period: yearly ? "yearly" : "monthly", amount: a, currency: "TRY", billDay: (!yearly && hasBillDay) ? billDay : nil,
                                payMethod: clean(method), exitFee: hasEnd ? clean(exitFee) : nil, priceClause: clean(priceClause),
                                keyTerms: keyTerms.isEmpty ? nil : keyTerms, note: clean(note), created: contract?.created))
        case .product:
            guard let n = clean(name) else { error = "Ürünün adını yaz."; return }
            if warrantyEnd < start { error = "Garanti bitişi alıştan sonra olmalı."; return }
            store.save(Product(id: product?.id ?? Store.newID("pr"), name: n, bought: Day.key(start), price: TL.parse(amount), seller: clean(seller),
                               warrantyEnd: Day.key(warrantyEnd), note: clean(note), created: product?.created))
        case .document:
            return
        }
        dismiss()
    }
}
