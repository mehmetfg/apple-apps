import sys, json, warnings, numpy as np, librosa, scipy.signal as sg
warnings.filterwarnings("ignore")
def analyse(f):
    y, sr = librosa.load(f, sr=22050, mono=True)
    y = y / (np.max(np.abs(y)) + 1e-9)
    hop = 110
    f0, vf, vp = librosa.pyin(y, fmin=65, fmax=420, sr=sr, frame_length=1024, hop_length=hop)
    rms = librosa.feature.rms(y=y, frame_length=1024, hop_length=hop)[0]
    n = min(len(f0), len(rms)); f0, vf, vp, rms = f0[:n], vf[:n], vp[:n], rms[:n]
    db = 20*np.log10(rms+1e-9)
    speak = db > (np.percentile(db, 95) - 22)
    voiced = vf & speak
    med = np.median(f0[voiced]); st = 12*np.log2(f0/med)
    # phrases: speech runs split by pauses >= 150 ms
    fr = hop/sr; phrases=[]; pauses=[]; i=0
    while i<n:
        if speak[i]:
            j=i
            gap=0; k=i
            while k<n and gap*fr<0.10:
                if speak[k]: j=k; gap=0
                else: gap+=1
                k+=1
            phrases.append((i,j+1)); i=k
        else:
            j=i
            while j<n and not speak[j]: j+=1
            if phrases and j<n: pauses.append((j-i)*fr)
            i=j
    pm=[]; pr=[]; fin=[]; plev=[]
    for a,b in phrases:
        v=voiced[a:b]
        if v.sum()<30: continue
        s=st[a:b][v]; pm.append(np.median(s)); pr.append(np.percentile(s,90)-np.percentile(s,10))
        fin.append(np.median(s[-24:])-np.median(s))
        plev.append(20*np.log10(np.sqrt(np.mean(rms[a:b][speak[a:b]]**2))))
    # frame-to-frame movement inside voiced runs
    d=np.abs(np.diff(st)); ok=voiced[1:]&voiced[:-1]; d=d[ok]
    # short-term level (400 ms) over speech
    w=int(0.4/fr); sl=[]
    for a in range(0,n-w,w//2):
        seg=rms[a:a+w][speak[a:a+w]]
        if len(seg)>w*0.6: sl.append(20*np.log10(np.sqrt(np.mean(seg**2))))
    # syllable nuclei: peaks of 8 Hz-smoothed envelope
    env=sg.filtfilt(*sg.butter(2, 8/(0.5/fr)), rms)
    pk,_=sg.find_peaks(env, prominence=0.02*np.max(env), distance=int(0.07/fr))
    pk=pk[speak[pk]]; ioi=np.diff(pk)*fr; ioi=ioi[ioi<0.5]
    npvi=100*np.mean(np.abs(np.diff(ioi))/((ioi[1:]+ioi[:-1])/2))
    # spectrum
    S=np.abs(librosa.stft(y, n_fft=2048, hop_length=hop))**2; S=S[:, :n][:, speak]
    fq=librosa.fft_frequencies(sr=sr, n_fft=2048); tot=S.sum()
    band=lambda a,b: 10*np.log10(S[(fq>=a)&(fq<b)].sum()/tot+1e-12)
    # periodicity: mean voiced probability in voiced frames; share of speech that is voiced
    return dict(file=f, f0=med, spread=np.percentile(st[voiced],90)-np.percentile(st[voiced],10),
        phr_n=len(pm), phr_med_sd=np.std(pm), phr_range=np.mean(pr), phr_range_sd=np.std(pr), final=np.mean(fin), final_sd=np.std(fin),
        dstep_p95=np.percentile(d,95), jumps=100*np.mean(d>1),
        lev_phr_sd=np.std(plev), lev_st_range=np.percentile(sl,90)-np.percentile(sl,10),
        syl=len(pk)/ (speak.sum()*fr), ioi_cv=np.std(ioi)/np.mean(ioi), npvi=npvi,
        pause_n=len(pauses), pause_mean=np.mean(pauses) if pauses else 0, pause_cv=(np.std(pauses)/np.mean(pauses)) if pauses else 0,
        speech_share=speak.mean(), voiced_share=voiced.sum()/speak.sum(), vprob=np.mean(vp[voiced]),
        b_low=band(80,250), b_mid=band(250,1000), b_up=band(1000,2500), b_pres=band(2500,5000), b_air=band(5000,10000))
rows=[analyse(f) for f in sys.argv[1:]]
keys=[k for k in rows[0] if k!="file"]
print(f"{'':16s}"+"".join(f"{r['file'][:13]:>14s}" for r in rows))
for k in keys: print(f"{k:16s}"+"".join(f"{r[k]:14.2f}" for r in rows))
json.dump(rows, open("stab.json","w"), default=float)
