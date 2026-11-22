from pathlib import Path
P=Path(__file__).parent
# Original vector character, created for this review concept. Not an icon or a Duolingo asset.
def character(pose='wave',fill='#FFB34F',shade='#E88C31',scarf='#66B85E'):
 head='''<path d="M88 76C65 57 44 72 50 95C25 121 29 169 43 199C55 225 86 237 128 236C170 236 202 218 210 185C217 151 211 118 190 97C200 74 177 57 158 76C136 66 111 66 88 76Z" fill="COLOR"/>
<path d="M61 88C60 76 73 76 79 85M169 85C176 77 187 79 185 89" stroke="SHADE" stroke-width="8" stroke-linecap="round" fill="none"/>
<ellipse cx="105" cy="145" rx="30" ry="28" fill="#FFF4DA"/><ellipse cx="155" cy="145" rx="30" ry="28" fill="#FFF4DA"/>
<ellipse cx="112" cy="145" rx="7" ry="11" fill="#553C26"/><ellipse cx="151" cy="145" rx="7" ry="11" fill="#553C26"/>
<circle cx="114" cy="141" r="2.5" fill="white"/><circle cx="153" cy="141" r="2.5" fill="white"/>
<ellipse cx="132" cy="176" rx="38" ry="25" fill="#FFD18A"/><rect x="119" y="162" width="26" height="17" rx="8" fill="#694527"/>
<path d="M132 179V186M120 187Q132 198 144 187" stroke="#694527" stroke-width="5" stroke-linecap="round" fill="none"/>
<ellipse cx="76" cy="169" rx="13" ry="8" fill="#F39348"/><ellipse cx="183" cy="169" rx="13" ry="8" fill="#F39348"/>'''
 body='''<ellipse cx="126" cy="288" rx="87" ry="12" fill="#D5DDD1"/><path d="M74 202C57 226 55 262 69 276C83 288 172 287 187 271C198 253 182 217 169 204Z" fill="SHADE"/><path d="M80 205C65 230 69 260 82 266C108 279 161 273 176 258C184 241 172 217 164 206Z" fill="COLOR"/><ellipse cx="91" cy="275" rx="27" ry="13" fill="COLOR"/><ellipse cx="163" cy="275" rx="27" ry="13" fill="COLOR"/><path d="M77 224Q126 245 174 222L177 237Q124 259 75 239Z" fill="SCARF"/><path d="M146 240L156 270L174 265L166 235Z" fill="SCARF"/>'''
 if pose=='wave':arms='<path d="M59 216C38 208 29 183 19 187C8 194 28 236 58 243Z" fill="COLOR"/><path d="M184 220C203 205 220 212 210 229L187 246Z" fill="COLOR"/>'
 elif pose=='celebrate':arms='<path d="M65 219C42 203 35 168 19 177C9 188 26 236 60 246Z" fill="COLOR"/><path d="M183 217C204 200 215 161 231 171C245 183 222 228 190 243Z" fill="COLOR"/>'
 elif pose=='camera':arms='<path d="M58 218C76 214 96 227 94 240L58 247Z" fill="COLOR"/><path d="M182 217C161 214 145 227 148 241L187 247Z" fill="COLOR"/>'
 elif pose=='read':arms='<path d="M54 217C76 209 88 224 93 242L57 247Z" fill="COLOR"/><path d="M185 217C161 213 148 228 147 242L191 245Z" fill="COLOR"/>'
 else:arms='<ellipse cx="62" cy="233" rx="18" ry="25" fill="COLOR"/><ellipse cx="184" cy="233" rx="18" ry="25" fill="COLOR"/>'
 extra=''
 if pose=='camera':extra='<rect x="81" y="221" width="94" height="59" rx="14" fill="#467687"/><path d="M103 221V213H137V221" fill="#467687"/><rect x="89" y="229" width="78" height="40" rx="9" fill="#609BA9"/><circle cx="130" cy="248" r="21" fill="#E9F7EC"/><circle cx="130" cy="248" r="14" fill="#2C5967"/><circle cx="134" cy="244" r="5" fill="#8DC4D4"/>'
 if pose=='read':extra='<path d="M73 226Q100 219 129 233Q155 219 184 226V273Q154 266 129 279Q100 267 73 273Z" fill="#5F9BD1"/><path d="M81 225Q105 220 129 233Q150 223 176 226V264Q151 260 129 273Q107 263 81 266Z" fill="#FFF8E8"/><path d="M129 235V271" stroke="#D0C8AC" stroke-width="3"/><path d="M90 239L115 245M90 249L115 255M141 245L167 239M141 255L167 249" stroke="#CABF9D" stroke-width="3" stroke-linecap="round"/>'
 if pose=='celebrate':extra='<path d="M90 79L81 49L107 59L126 33L145 60L173 49L162 81Z" fill="#65B647"/><ellipse cx="126" cy="81" rx="36" ry="8" fill="#509539"/>'
 svg=f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 310" role="img"><title>团团，原创橘黄色陪伴小熊</title>{body}{arms}{head}{extra}</svg>'
 return svg.replace('COLOR',fill).replace('SHADE',shade).replace('SCARF',scarf)
for pose in ['wave','celebrate','camera','read','stand']:(P/f'tuantuan-{pose}.svg').write_text(character(pose))
for name,color,shade,scarf in [('green','#A2CF76','#7BAD54','#478F78'),('blue','#8AC7DE','#65ABC9','#F0AB44'),('pink','#EFADA1','#D78D82','#528D9F')]:
 (P/f'friend-{name}.svg').write_text(character('stand',color,shade,scarf))
