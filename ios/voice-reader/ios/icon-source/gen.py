import math
P=[(600,1130),(600,760),(330,660),(392,312)]
def pt(t):
    a=[(1-t)**3,3*(1-t)**2*t,3*(1-t)*t*t,t**3]
    return (sum(a[i]*P[i][0] for i in range(4)), sum(a[i]*P[i][1] for i in range(4)))
def tan(t):
    e=1e-4; x0,y0=pt(max(0,t-e)); x1,y1=pt(min(1,t+e)); d=math.hypot(x1-x0,y1-y0); return ((x1-x0)/d,(y1-y0)/d)
N=140; L=[];R=[]
for i in range(N+1):
    t=i/N; x,y=pt(t); tx,ty=tan(t); nx,ny=-ty,tx
    w=(1-t)**1.2*128+4
    L.append((x+nx*w,y+ny*w)); R.append((x-nx*w,y-ny*w))
road="M"+" L".join(f"{x:.1f} {y:.1f}" for x,y in L+R[::-1])+" Z"
CL=[];CR=[]
for i in range(N+1):
    t=0.04+0.86*i/N; x,y=pt(t); tx,ty=tan(t); nx,ny=-ty,tx
    w=(1-t)**1.2*9+0.6
    CL.append((x+nx*w,y+ny*w)); CR.append((x-nx*w,y-ny*w))
line="M"+" L".join(f"{x:.1f} {y:.1f}" for x,y in CL+CR[::-1])+" Z"
dashes=[]
def svg(bg1,bg2,book,r1,r2,dash,r3):
    d="".join(f'<polyline points="{p}" fill="none" stroke="{dash}" stroke-width="{w:.1f}" stroke-linecap="round"/>' for p,w in dashes)
    pages="".join(f'<rect x="{312+dx}" y="{262-dy}" width="400" height="530" rx="62" fill="none" stroke="{book}" stroke-width="22" transform="rotate({rot} 512 527)"/>' for dx,dy,rot in [(34,40,3),(66,80,6)])
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs><linearGradient id="bg" x1="0" y1="0" x2="0.4" y2="1"><stop offset="0" stop-color="{bg1}"/><stop offset="1" stop-color="{bg2}"/></linearGradient>
<linearGradient id="rd" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="{r1}"/><stop offset="0.55" stop-color="{r2}"/><stop offset="1" stop-color="{r3}"/></linearGradient>
<clipPath id="c"><rect width="1024" height="1024"/></clipPath>
<mask id="gap"><rect width="1024" height="1024" fill="white"/><rect x="290" y="240" width="444" height="574" rx="80" fill="black"/></mask></defs>
<rect width="1024" height="1024" fill="url(#bg)"/>
<clipPath id="tr"><polygon points="452,300 452,0 1024,0 1024,1024 690,1024 690,300"/></clipPath>
<g mask="url(#gap)" clip-path="url(#tr)">{pages}</g>
<rect x="312" y="262" width="400" height="530" rx="62" fill="{book}"/>
<g clip-path="url(#c)"><path d="{road}" fill="url(#rd)"/><path d="{line}" fill="{dash}" opacity="0.92"/></g>
</svg>'''
open("light.svg","w").write(svg("#1287DA","#00507F","#FFFFFF","#E8200A","#FF5A2C","#FFFFFF","#FF8A3D"))
open("dark.svg","w").write(svg("#0E1A2A","#04080F","#EAF2FA","#E8200A","#FF5A2C","#EAF2FA","#FF8A3D"))
open("tinted.svg","w").write(svg("#000000","#000000","#FFFFFF","#7A7A7A","#9A9A9A","#FFFFFF","#B0B0B0"))
