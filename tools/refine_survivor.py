"""Original survivor tailoring pass; uses the existing rig, palette and metric scale."""
import math
import bpy


def refine(parts, materials, make_part):
    def part(*args):
        return make_part(*args, detail=True)
    def mesh(name, vertices, faces, material, bone, smooth=False):
        data=bpy.data.meshes.new(name)
        data.from_pydata(vertices, [], faces)
        data.materials.append(materials[material])
        obj=bpy.data.objects.new(name,data)
        bpy.context.collection.objects.link(obj)
        obj.vertex_groups.new(name=bone).add(list(range(len(vertices))),1,'REPLACE')
        for face in data.polygons: face.use_smooth=smooth
        parts.append(obj)
        return obj

    # Continuous jaw / cheek / brow / skull sections replace the spherical head.
    for obj in list(parts):
        if obj.name in ['DD_Head','DD_Nose','DD_Mouth']:
            parts.remove(obj)
            bpy.data.objects.remove(obj,do_unlink=True)
    vertices=[];faces=[];segments=24
    profiles=[(1.518,.048,.062),(1.54,.073,.087),(1.575,.093,.102),
              (1.615,.111,.109),(1.65,.122,.112),(1.68,.116,.109),
              (1.713,.119,.112),(1.747,.108,.104),(1.776,.071,.074),(1.787,.018,.025)]
    for z,rx,ry in profiles:
        for i in range(segments):
            phi=i*math.tau/segments
            x=rx*math.cos(phi);y=ry*math.sin(phi)
            front=max(0,-math.sin(phi))**10
            # Small continuous nasal bridge; eye sockets sit either side.
            nose=.033*math.exp(-((z-1.646)/.028)**2)*math.exp(-(x/.026)**2)
            socket=.009*math.exp(-((z-1.674)/.018)**2)*math.exp(-((abs(x)-.052)/.028)**2)
            y+=front*(socket-nose)
            vertices.append((x,y-.005,z))
    for j in range(len(profiles)-1):
        for i in range(segments):
            a=j*segments+i;b=j*segments+(i+1)%segments
            faces.append((a,b,b+segments,a+segments))
    faces += [tuple(reversed(range(segments))),tuple(range((len(profiles)-1)*segments,len(profiles)*segments))]
    mesh('DD_Head',vertices,faces,'skin','head',True)
    part('LipLine',(0,-.107,1.583),(.046,.008,.007),'wood','head',.002)
    for obj in parts:
        if obj.name.startswith('DD_Eye_'):
            obj.location.z=1.674
            obj.location.y=-.104
    # The fringe is part of the scalp surface, not floating cards above the forehead.
    hair=next(obj for obj in parts if obj.name=='DD_SculptedHair')
    for index,vertex in enumerate(hair.data.vertices):
        ring=index//24
        phi=(index%24)*math.tau/24
        # Longer nape, swept asymmetric fringe and a subtle parting ridge.
        front=max(0,-math.sin(phi))
        limit=1.72+.23*math.sin(phi)-.35*front**4+front*.07*math.cos(phi*3)
        theta=.015+(limit-.015)*ring/8
        ridge=.004*math.sin(phi*7+theta*2)*math.sin(theta)**2
        vertex.co=((.144+ridge)*math.sin(theta)*math.cos(phi)+.004*math.cos(theta),
                   -.002+(.148+ridge)*math.sin(theta)*math.sin(phi),
                   1.65+(.158+ridge)*math.cos(theta))
    # Closed, tapered locks overlap the scalp. No transparent cards or floating tips.
    for index in range(11):
        phi=-math.pi+.16+index*(math.pi-.32)/10
        vertices=[];faces=[]
        for row in range(5):
            t=row/4
            forehead=max(0,-math.sin(phi))**4
            theta=.50+t*(.96-.29*forehead+.06*math.sin(index*1.7))
            azimuth=phi+.30*(1-t)
            width=.20*(1-.75*t)
            for side,raised in [(-1,0),(0,.009),(1,0),(0,-.003)]:
                angle=azimuth+side*width
                radius=.151+raised
                vertices.append((radius*math.sin(theta)*math.cos(angle),
                                 -.002+radius*math.sin(theta)*math.sin(angle),
                                 1.65+(.165+raised)*math.cos(theta)))
        for row in range(4):
            for side in range(4):
                a=row*4+side;b=row*4+(side+1)%4
                faces.append((a,b,b+4,a+4))
        faces += [(3,2,1,0),(16,17,18,19)]
        mesh('DD_SweptLock_'+str(index),vertices,faces,'hair_player','head',True)
    # Replace the old rounded collar blobs with tailored folded surfaces.
    for obj in list(parts):
        if obj.name.startswith('DD_Collar'):
            parts.remove(obj)
            bpy.data.objects.remove(obj,do_unlink=True)
    for sign in [-1,1]:
        brow=part('Brow',(sign*.052,-.111,1.697),(.048,.010,.010),'hair_player','head',.003)
        brow.rotation_euler.y=sign*.12
    # Tailored coat folds follow compression at elbows, waist and cuffs.
    for obj in parts:
        if obj.name.startswith(('DD_CoatSleeve','DD_TrouserLeg')):
            for vertex in obj.data.vertices:
                x,y,z=vertex.co
                center=(1.10 if 'Sleeve' in obj.name else .49)
                influence=math.exp(-((z-center)/.13)**2)
                vertex.co.y+=.018*influence*math.sin(z*85+x*18)
                # Uneven cloth compression changes the silhouette at joints.
                vertex.co.x+=math.copysign(.007*influence*math.cos(z*73),x)
    # Open collar/lapels sit against the torso, with a visible inner shirt.
    mesh('DD_InnerShirt',[(-.065,-.121,1.44),(.065,-.121,1.44),(.045,-.169,1.18),(-.045,-.169,1.18)],
         [(3,2,1,0)],'linen','spine')
    for sign in [-1,1]:
        mesh('DD_Lapel',[(sign*.055,-.13,1.46),(sign*.145,-.13,1.42),
             (sign*.115,-.165,1.34),(sign*.045,-.176,1.25),(sign*.032,-.15,1.40)],
             ([(4,2,1,0),(3,2,4)] if sign>0 else [(0,1,2,4),(4,2,3)]),'canvas','spine')
        part('PocketFlap',(sign*.12,-.211,1.205),(.145,.018,.045),'player_jacket','spine',.008)
        part('PocketSnap',(sign*.12,-.223,1.20),(.015,.009,.015),'steel','spine',.004)
        part('ChestPocket',(sign*.11,-.166,1.33),(.105,.025,.09),'player_jacket','spine',.012)
        part('ChestFlap',(sign*.11,-.184,1.363),(.11,.012,.022),'canvas','spine',.004)
        side='L' if sign<0 else 'R'
        part('Cuff_'+side,(sign*.36,0,.86),(.124,.141,.045),'boots','forearm_'+side,.018)
        # Palm is shortened, with four fingers and a separate thumb in a relaxed pose.
        palm=next(o for o in parts if o.name=='DD_Hand_'+side)
        for v in palm.data.vertices: v.co.z*=.65
        for finger in range(4):
            part('Hand_Finger_'+side+str(finger),(sign*.36+(finger-1.5)*.021,-.021,.741+abs(finger-1.5)*.006),
                 (.021,.049,.071),'skin','hand_'+side)
        thumb=part('Hand_Thumb_'+side,(sign*.309,-.027,.784),(.036,.051,.075),'skin','hand_'+side)
        thumb.rotation_euler.y=sign*.35
        part('CargoPocket_'+side,(sign*.235,.005,.72),(.035,.17,.155),'trousers','thigh_'+side,.012)
        part('CargoFlap_'+side,(sign*.256,.005,.777),(.018,.174,.035),'canvas','thigh_'+side,.005)
        for j in range(3):
            part('BootLace_'+side+str(j),(sign*.14,-.087-j*.026,.155-j*.012),(.096,.012,.009),'canvas','foot_'+side,.003)
    # Pack has a gusset, lower pocket, paired closures and reinforced edging.
    part('PackLowerPocket',(0,.297,1.16),(.265,.065,.135),'canvas','spine',.022)
    for sign in [-1,1]:
        part('PackSidePouch',(sign*.183,.205,1.22),(.075,.13,.19),'canvas','spine',.022)
        part('PackClosure',(sign*.10,.337,1.31),(.027,.014,.16),'boots','spine',.004)
        part('PackClasp',(sign*.10,.349,1.275),(.041,.014,.033),'steel','spine',.006)
        part('PackSeam',(sign*.143,.305,1.20),(.009,.009,.25),'linen','spine',.003)
    # A bent carrying loop is visible above the pack rather than another solid box.
    mesh('DD_PackHandle',[(-.055,.245,1.405),(-.05,.245,1.46),(.05,.245,1.46),(.055,.245,1.405),
                         (-.04,.245,1.405),(-.035,.245,1.443),(.035,.245,1.443),(.04,.245,1.405)],
         [(0,1,5,4),(1,2,6,5),(2,3,7,6)],'boots','spine')
