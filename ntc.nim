## The nimTUROCHAMP chess engine,
## an implementation of TUROCHAMP in Nim using the Sunfish move generator

import tables, strutils, times, algorithm, math
from strformat import fmt
from unicode import reversed, swapCase

const
        A1 = 91
        H1 = 98
        A8 = 21
        H8 = 28
        ini = ( "         \n" &
                "         \n" &
                " rnbqkbnr\n" &
                " pppppppp\n" &
                " ........\n" &
                " ........\n" &
                " ........\n" &
                " ........\n" &
                " PPPPPPPP\n" &
                " RNBQKBNR\n" &
                "         \n" &
                "         \n"
        )
        emp = ( "         \n" &
                "         \n" &
                " ........\n" &
                " ........\n" &
                " ........\n" &
                " ........\n" &
                " ........\n" &
                " ........\n" &
                " ........\n" &
                " ........\n" &
                "         \n" &
                "         \n"
        )
        N = -10
        E = 1
        S = 10
        W = -1
        dirs = to_table({'P': [N, N+N, N+W, N+E, 0, 0, 0, 0],
        'N': [N+N+E, E+N+E, E+S+E, S+S+E, S+S+W, W+S+W, W+N+W, N+N+W],
        'B': [N+E, S+E, S+W, N+W, 0, 0, 0, 0],
        'R': [N, E, S, W, 0, 0, 0, 0],
        'Q': [N, E, S, W, N+E, S+E, S+W, N+W],
        'K': [N, E, S, W, N+E, S+E, S+W, N+W]
        })
        piece = to_table({'P': 1.0, 'N': 3.0, 'B': 3.5, 'R': 5.0, 'Q': 10.0, 'K': 1000.0})

var
        MAXPLIES* = 4                    ## brute-force search depth
        QPLIES* = MAXPLIES + 4           ## selective search depth
        NODES = 0

type Position* = object
        board*: string
        score*: float
        wc_w*: bool
        wc_e*: bool
        bc_w*: bool
        bc_e*: bool
        ep*: int
        kp*: int

proc render*(x: int): string =
        ## convert index to square name
        var r = int((x - A8) / 10)
        var f = (x - A8) mod 10

        result = fmt"{char(f + ord('a'))}{8 - r}"

proc parse*(c: string, inv = false): int =
        ## convert square name to index
        var f = ord(c[0]) - ord('a')
        var r = ord(c[1]) - ord('1')
        if inv:
                f = 7 - f
                r = 7 - r
        #echo f, " ", r
        return A1 + f - 10 * r

proc newgame*(): Position =
        ## create a new board in the starting position
        Position(board: ini, score: 0, wc_w: true, wc_e: true,
                bc_w: true, bc_e: true, ep: 0, kp: 0) 

proc put(board: string, at: int, piece: char): string =
        ## put piece at board location
        return board[0..at-1] & piece & board[at+1..119]

proc rotate*(s: Position): Position =
        ## rotate board for other player's turn
        var ep = 0
        var kp = 0
        if s.ep > 0:
                ep = 119 - s.ep
        if s.kp > 0:
                kp = 119 - s.kp
        return Position(board: s.board.reversed.swapCase(),
                score: -s.score, wc_w: s.bc_w, wc_e: s.bc_e, bc_w: s.wc_w, bc_e: s.wc_e,
                ep: ep, kp: kp)

proc fromfen*(fen: string): Position =
        ## accept a FEN and return a board
        var b = emp

        var f = fen.split(" ")[0]
        var cas = fen.split(" ")[2]
        var enpas = fen.split(" ")[3]

        var i = 0
        var j = 0

        for x in f:
                var a = ord(x)
                if (a > 48) and (a < 57):
                        i = i + (a - 48)
                elif a == 47:
                        i = 0
                        inc j
                else:
                        b[A8 + 10*j + i] = x
                        inc i

        var ep = 0
        if enpas != "-":
                ep = parse(enpas)

        var pos = Position(board: b, score: 0, wc_w: cas.contains('Q'), wc_e: cas.contains('K'),
                        bc_w: cas.contains('K'), bc_e: cas.contains('Q'), ep: ep, kp: 0)

        if fen.split(" ")[1] == "b":
                pos = pos.rotate()
        return pos

proc gen_moves*(s: Position): seq[(int, int)] =
        ## generate all pseudo-legal moves in a position
        for i in 0..119:
                var p = s.board[i]
                if not p.isUpperAscii():
                        continue
                #echo i, " ", render(i)
                for d in dirs[p]:
                        if d == 0:
                                break
                        var j = i + d
                        while true:
                                #echo render(j)
                                var q = s.board[j]
                                if q.isSpaceAscii() or q.isUpperAscii():
                                        break
                                if p == 'P' and d in [N, N+N] and q != '.':
                                        break
                                if p == 'P' and d == N+N and (i < A1+N or
                                                s.board[i+N] != '.'):
                                        break
                                if p == 'P' and d in [N+W, N+E] and q == '.' and
                                                not (j in [s.ep, s.kp, s.kp-1, s.kp+1]):
                                        break
                                result.add((i, j))
                                if p == 'P' or p == 'N' or p == 'K' or
                                                q.isLowerAscii():
                                        break
                                if i == A1 and s.board[j+E] == 'K' and s.wc_w:
                                        result.add((j+E, j+W))
                                if i == H1 and s.board[j+W] == 'K' and s.wc_e:
                                        result.add((j+W, j+E))
                                j = j + d

proc value(s: Position, fr: int, to: int): float =
        ## compute score difference due to given move
        let
                p = s.board[fr]
                q = s.board[to]
        if q.isLowerAscii():
                result += piece[q.toUpperAscii()]
        if p == 'P':
                if (A8 <= to) and (to <= H8):
                        result += piece['Q'] - piece['P']
                if to == s.ep:
                        result += piece['P']

proc move*(s: Position, fr: int, to: int): Position =
        ## carry out a move on the board
        let
                p = s.board[fr]
                #q = s.board[to]
        var
                board = s.board
                score = s.score + s.value(fr, to)
                wc_w = s.wc_w
                wc_e = s.wc_e
                bc_w = s.bc_w
                bc_e = s.bc_e
                ep = 0
                kp = 0
        board = put(board, to, board[fr])
        board = put(board, fr, '.')
        if fr == A1: wc_w = false
        if fr == H1: wc_e = false
        if to == A8: bc_e = false
        if to == H8: bc_w = false

        if p == 'K':
                wc_w = false
                wc_e = false
                if abs(to - fr) == 2:
                        kp = int((to + fr) / 2)
                        if to < fr:
                                board = put(board, A1, '.')
                        else:
                                board = put(board, H1, '.')
                        board = put(board, kp, 'R')

        if p == 'P':
                if (A8 <= to) and (to <= H8):
                        board = put(board, to, 'Q')
                if to - fr == 2*N:
                        ep = fr + N
                if to == s.ep:
                        board = put(board, to+S, '.')

        return Position(board: board, score: score,
                wc_w: wc_w, wc_e: wc_e, bc_w: bc_w, bc_e: bc_e, ep: ep, kp: kp)

proc searchmax(b: Position, ply: int, alpha: float, beta: float): float =
        ## Negamax search function
        inc NODES
        if ply >= QPLIES:
                return b.score
        if not ('K' in b.board): return -9999
        if not ('k' in b.board): return  9999
        var moves = gen_moves(b)
        if ply > MAXPLIES:
                var mov2: seq[(int, int)]
                for i in 0..len(moves)-1:
                        if b.board[moves[i][1]] != '.':
                                mov2.add((moves[i][0], moves[i][1]))
                moves = mov2
        if len(moves) == 0: return b.score
        var al = alpha
        for i in 0..len(moves)-1:
                var c = b.move(moves[i][0], moves[i][1])
                var d = c.rotate()
                var t = searchmax(d, ply + 1, -beta, -al)
                t = -t
                if t >= beta:
                        return beta
                if t > al:
                        al = t
        return al

proc myCmp(x, y: tuple): int =
        if x[0] > y[0]: -1 else: 1

proc isblack*(pos: Position): bool =
        ## is it Black's turn?
        if pos.board.startsWith('\n'): true else: false

proc attacks*(pos: Position, x: int): seq[int] =
        ## return attacked empty and enemy squares
        var moves = pos.gen_moves()
        for n in 0..len(moves)-1:
                let i = moves[n][0]
                let j = moves[n][1]
                if i == x:
                        result.add(j)

proc defenders*(pos: Position, x: int): seq[int] =
        ## get list of defenders for a square
        var db = Position(board: pos.board, score: pos.score,
                        wc_w: pos.wc_w, wc_e: pos.wc_e,
                        bc_w: pos.bc_w, bc_e: pos.bc_e, ep: pos.ep, kp: pos.kp)
        db.board[x] = 'p'
        var moves = db.gen_moves()
        for n in 0..len(moves)-1:
                let i = moves[n][0]
                let j = moves[n][1]
                if j == x:
                        result.add(i)

proc turing(s: Position): float =
        ## evaluate Turing positional criteria

        var bking = false

        for i in 0..119:
                var p = s.board[i]
                var tt: float
                if not p.isUpperAscii(): continue
                        
                var a = s.attacks(i)
                # Black King
                for j in a:
                        if s.board[j] == 'k': bking = true

                # piece mobility
                if p != 'P':
                        if len(a) > 0:
                                for j in a:
                                        if s.board[j] == '.': tt += 1
                                        else: tt += 2
                        result += sqrt(tt)
                
                # pieces defended
                if p == 'R' or p == 'B' or p == 'N':
                        var ndef = len(s.defenders(i))
                        if ndef > 0: result += 1
                        if ndef > 1: result += 0.5

                # King safety
                if p == 'K':
                        var ks = Position(board: s.board, score: s.score,
                                        wc_w: s.wc_w, wc_e: s.wc_e,
                                        bc_w: s.bc_w, bc_e: s.bc_e, ep: s.ep, kp: s.kp)
                        tt = 0
                        ks.board[i] = 'Q'
                        var ka = ks.attacks(i)
                        if len(ka) > 0:
                                for j in ka:
                                        if s.board[j] == '.': tt += 1
                                        else: tt += 2
                        result -= sqrt(tt)

                # Pawns
                if p == 'P':
                        var rad = int(6 - (i - A8) / 10)
                        result += 0.2 * float(rad)

                        var pdef = s.defenders(i)
                        var pawndef = false
                        for k in pdef:
                                if s.board[k] != 'P':
                                        pawndef = true
                        if pawndef: result += 0.3

        # Black King
        if bking: result += 0.5

proc getmove*(b: Position): string =
        ## get computer move for board position
        NODES = 0
        var start = epochTime()
        var moves = gen_moves(b)
        var ll: seq[(float, string, string, int, int)]
                
        for i in 0..len(moves)-1:
                var fr = render(moves[i][0])
                var to = render(moves[i][1])
                var castle: float
                if b.board[moves[i][0]] == 'K' and abs(moves[i][0] - moves[i][1]) == 2: castle += 1
                var c = b.move(moves[i][0], moves[i][1])
                if c.isblack():
                        if c.bc_w or c.bc_e: castle += 1
                else:
                        if c.wc_w or c.wc_e: castle += 1
                var d = c.rotate()
                var t = searchmax(d, 2, -1e6, 1e6)
                t = -t
                #echo fr, to, " ", t, " ", c.turing()
                ll.add((t + (c.turing() + castle) / 1000.0, fr, to, moves[i][0], moves[i][1]))

        ll.sort(myCmp)

        var diff = epochTime() - start

        #var c = b.move(ll[0][3], ll[0][4])
        echo fmt"info depth {MAXPLIES} seldepth {QPLIES} score cp {int(100*ll[0][0])} time {int(1000*diff)} nodes {NODES}"
        return ll[0][1] & ll[0][2]

when isMainModule:
        var b: Position
        var side = true         # White's turn

        proc getgame(x: string): Position =
                ## construct board from startpos moves command, e.g. from Cute Chess
                var b = newgame()
                side = true
                let mm = x.split(' ')[3..^1]
                var inv = false
                for i in mm:
                        var fr = parse(i[0..1], inv = inv)
                        var to = parse(i[2..3], inv = inv)
                        var c = b.move(fr, to)
                        side = not side

                        var d = c.rotate()
                        b = d
                        inv = not inv
                return b

        proc shredder(l: string): string =
                ## fix Shredder FENs
                let x = l.split(" ")
                return x[0..5].join(" ") & " 0 1 " & x[6..^1].join(" ")

        proc getgame_fen(x: string): Position =
                ## construct board from FEN command, e.g. from Picochess

                var inv: bool
                var l: string

                if x.split(" ")[6] == "moves": l = shredder(x) else: l = x
                let ff = l.split(" ")[2..7]
                let ff2 = ff.join(" ")

                var b = fromfen(ff2)
                if " w " in ff2:
                        side = true
                        inv = false
                else:
                        side = false
                        inv = true

                if len(l.split(" ")) > 8:
                        let mm = l.split(" ")[9..^1]
                        for i in mm:
                                var fr = parse(i[0..1], inv = inv)
                                var to = parse(i[2..3], inv = inv)
                                var c = b.move(fr, to)
                                side = not side

                                var d = c.rotate()
                                b = d
                                inv = not inv
                return b

        proc mirror(x: string): string =
                ## mirror move for Black
                var f1 = char(ord('a') + 7 - (ord(x[0]) - ord('a')))
                var f2 = char(ord('a') + 7 - (ord(x[2]) - ord('a')))
                var r1 = char(ord('1') + 7 - (ord(x[1]) - ord('1')))
                var r2 = char(ord('1') + 7 - (ord(x[3]) - ord('1')))
                return f1 & r1 & f2 & r2

        while true:
                var l = readLine(stdin)

                if l == "quit":
                        break
                if l == "?":
                        echo b.board
                if l == "uci":
                        echo "id name nimTUROCHAMP"
                        echo "id author Martin C. Doege"
                        echo fmt"option name maxplies type spin default {MAXPLIES} min 1 max 1024"
                        echo fmt"option name qplies type spin default {QPLIES} min 1 max 1024"
                        echo "uciok"
                if l == "isready":
                        if b.board == "":
                                b = newgame()
                                side = true
                        echo "readyok"
                if l == "ucinewgame" or l == "position startpos":
                        b = newgame()
                        side = true

                if l.startsWith("setoption name maxplies value"):
                        MAXPLIES = parseInt(l.split()[4])
                        echo "# maxplies ", MAXPLIES
                if l.startsWith("setoption name qplies value"):
                        QPLIES = parseInt(l.split()[4])
                        echo "# qplies ", QPLIES

                if l.startsWith("position startpos moves"):
                        b = l.getgame()
                if l.startsWith("position fen"):
                        b = l.getgame_fen()
                if l.startsWith("go"):
                        if b.board == "":
                                b = newgame()
                                side = true
                        var m = b.getmove()
                        if not side:
                                m = m.mirror()
                        side = not side
                        echo "bestmove ", m


