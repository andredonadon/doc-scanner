"""Prototype of a line-based page detector (not used by the app yet).

The app's detector (lib/services/scanner.dart) looks for closed page outlines
and fails when one side of the page is nearly invisible, e.g. white paper on a
white bedsheet. This prototype instead:

  1. finds long straight segments (Hough) on a normal and a sensitive edge map,
  2. merges segments lying on the same line, splits them into horizontal and
     vertical candidates (plus the four image borders),
  3. intersects every top/bottom/left/right combination into a quadrilateral,
  4. keeps quads with at least 3 sides lying on real edges, and scores them by
     area * edge support * (1 - strong edges just outside the sides), since a
     page side should not cut through text.

Usage:  python3 tool/edge_prototype.py photo.jpg overlay.jpg
Needs:  pip install opencv-python numpy
"""
import cv2, numpy as np, itertools, math, sys
DEBUG=False; SOFT=(20,60); SUPPORT_SOFT=False; MAXL=30
def detect(path, out):
    img=cv2.imread(path)
    s=600/max(img.shape[:2]); small=cv2.resize(img,None,fx=s,fy=s,interpolation=cv2.INTER_AREA)
    H,W=small.shape[:2]
    gray=cv2.GaussianBlur(cv2.cvtColor(small,cv2.COLOR_BGR2GRAY),(5,5),0)
    edges=cv2.Canny(gray,50,150)
    soft=cv2.Canny(gray,SOFT[0],SOFT[1])
    support=cv2.dilate(soft if SUPPORT_SOFT else edges,np.ones((3,3),np.uint8),iterations=2)
    segs=[]
    for e,th,ml,gap in ((edges,50,0.15,20),(soft,30,0.08,40)):
        g=cv2.HoughLinesP(e,1,np.pi/180,threshold=th,minLineLength=int(ml*max(W,H)),maxLineGap=gap)
        if g is not None: segs+=list(np.array(g).reshape(-1,4))
    m=0.02*max(W,H)
    segs=[g for g in segs if not ((min(g[0],g[2])<m and max(g[0],g[2])<m) or (min(g[0],g[2])>W-m) or (max(g[1],g[3])<m) or (min(g[1],g[3])>H-m))]
    hs,vs=[(0,0,W-1,0),(0,H-1,W-1,H-1)],[(0,0,0,H-1),(W-1,0,W-1,H-1)]
    for x1,y1,x2,y2 in segs:
        ang=math.degrees(math.atan2(y2-y1,x2-x1))%180
        (hs if (ang<35 or ang>145) else vs if 55<ang<125 else []).append((x1,y1,x2,y2))
    def merge(lines):
        cl=[]
        for x1,y1,x2,y2 in lines:
            ang=math.atan2(y2-y1,x2-x1)%math.pi
            rho=-x1*math.sin(ang)+y1*math.cos(ang)
            ln=math.hypot(x2-x1,y2-y1)
            for c in cl:
                da=abs(c['ang']-ang); da=min(da,math.pi-da)
                if da<math.radians(3) and abs(c['rho']-rho)<8:
                    c['len']+=ln
                    if ln>c['best']: c['best']=ln; c['seg']=(x1,y1,x2,y2)
                    break
            else: cl.append(dict(ang=ang,rho=rho,len=ln,best=ln,seg=(x1,y1,x2,y2)))
        cl.sort(key=lambda c:-c['len'])
        return [c['seg'] for c in cl[:MAXL]]
    hs=merge(hs[2:])+hs[:2]; vs=merge(vs[2:])+vs[:2]
    if DEBUG: print("H", [tuple(int(v) for v in l) for l in hs])
    def inter(a,b):
        x1,y1,x2,y2=a; x3,y3,x4,y4=b
        d=(x1-x2)*(y3-y4)-(y1-y2)*(x3-x4)
        if abs(d)<1e-6: return None
        t=((x1-x3)*(y3-y4)-(y1-y3)*(x3-x4))/d
        return (x1+t*(x2-x1), y1+t*(y2-y1))
    def fit(q):
        sides=[]
        for i in range(4):
            a,b=q[i],q[(i+1)%4]; hits=0; n=60
            for k in range(n):
                t=(k+.5)/n; x=round(a[0]+(b[0]-a[0])*t); y=round(a[1]+(b[1]-a[1])*t)
                if x<=3 or y<=3 or x>=W-4 or y>=H-4: hits+=0.5
                elif support[y,x]: hits+=1
            sides.append(hits/n)
        return sides
    strong=cv2.dilate(edges,np.ones((3,3),np.uint8))
    def outside(q):
        # Max over sides of the strong-edge density in a band just outside.
        cx=sum(p[0] for p in q)/4; cy=sum(p[1] for p in q)/4
        worst=0
        for i in range(4):
            a,b=q[i],q[(i+1)%4]
            dx,dy=b[0]-a[0],b[1]-a[1]; L=math.hypot(dx,dy) or 1
            nx,ny=dy/L,-dx/L
            mx,my=(a[0]+b[0])/2,(a[1]+b[1])/2
            if (mx+nx-cx)**2+(my+ny-cy)**2 < (mx-cx)**2+(my-cy)**2: nx,ny=-nx,-ny
            hits=tot=0
            for k in range(40):
                t=0.1+0.8*(k+.5)/40
                for d in (6,10,14,18,22,26):
                    x=round(a[0]+dx*t+nx*d); y=round(a[1]+dy*t+ny*d)
                    if 0<=x<W and 0<=y<H:
                        tot+=1; hits+=strong[y,x]>0
            if tot: worst=max(worst,hits/tot)
        return worst
    def area(q): return abs(sum(q[i][0]*q[(i+1)%4][1]-q[(i+1)%4][0]*q[i][1] for i in range(4)))/2
    best=None;bs=0
    for t,b in itertools.combinations(hs,2):
        for l,r in itertools.combinations(vs,2):
            pts=[inter(t,l),inter(t,r),inter(b,r),inter(b,l)]
            if any(p is None for p in pts): continue
            if any(p[0]<-0.05*W or p[0]>1.05*W or p[1]<-0.05*H or p[1]>1.05*H for p in pts): continue
            a=area(pts)
            if a<0.15*W*H: continue
            sides=fit(pts)
            if sum(v>=0.7 for v in sides)<3: continue
            f=sum(sides)/4
            o=outside(pts)
            sc=a*f*f*(1-o)**2
            if sc>bs: bs=sc;best=(pts,f)
    vis=small.copy()
    for x1,y1,x2,y2 in segs: cv2.line(vis,(int(x1),int(y1)),(int(x2),int(y2)),(255,0,0),1)
    if best:
        q=np.array(best[0],np.int32); cv2.polylines(vis,[q],True,(0,200,0),3)
    print(path, len(hs),len(vs), best and round(best[1],2), best and [tuple(round(c) for c in p) for p in best[0]])
    cv2.imwrite(out,vis)
detect(sys.argv[1],sys.argv[2])
