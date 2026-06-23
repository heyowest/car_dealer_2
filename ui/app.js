/* ============================================================================
   car_dealer_2 — showroom overlay logic

   Browsing: the overlay is purely visual; the game camera owns the mouse.
   Buying:   Lua grabs NUI focus and sends { action: 'confirm' }, we show the
             modal, and POST the user's choice back to Lua.
   ========================================================================== */

(() => {
    'use strict';

    const RESOURCE = 'car_dealer_2';
    const inGame = typeof window.GetParentResourceName === 'function' || !!window.invokeNative;

    // ---- elements ----------------------------------------------------------
    const $ = (id) => document.getElementById(id);
    const app = $('app');
    const els = {
        brandName: $('brandName'),
        brandSub: $('brandSub'),
        vehClass: $('vehClass'),
        vehIndex: $('vehIndex'),
        vehName: $('vehName'),
        vehPrice: $('vehPrice'),
        lblSpeed: $('lblSpeed'),
        lblAccel: $('lblAccel'),
        lblBraking: $('lblBraking'),
        lblHandling: $('lblHandling'),
        hintRotate: $('hintRotate'),
        hintZoom: $('hintZoom'),
        hintSwitch: $('hintSwitch'),
        hintSit: $('hintSit'),
        hintBuy: $('hintBuy'),
        hintExit: $('hintExit'),
        modal: $('modal'),
        confirmTitle: $('confirmTitle'),
        confirmBody: $('confirmBody'),
        confirmName: $('confirmName'),
        confirmPrice: $('confirmPrice'),
        btnCancel: $('btnCancel'),
        btnConfirm: $('btnConfirm'),
    };
    const fills = {};
    document.querySelectorAll('.stat__fill').forEach((el) => { fills[el.dataset.stat] = el; });

    // ---- helpers -----------------------------------------------------------
    const money = (n) => '$' + Number(n || 0).toLocaleString('en-US');
    const pct = (v) => Math.round(Math.max(0, Math.min(1, v || 0)) * 100) + '%';

    function post(name, body) {
        if (!inGame) return Promise.resolve({});
        return fetch(`https://${RESOURCE}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body || {}),
        }).catch(() => {});
    }

    function applyLabels(labels) {
        if (!labels) return;
        const set = (el, v) => { if (el && v != null) el.textContent = v; };
        set(els.brandName, labels.brand);
        set(els.brandSub, labels.daily);
        set(els.lblSpeed, labels.statSpeed);
        set(els.lblAccel, labels.statAccel);
        set(els.lblBraking, labels.statBraking);
        set(els.lblHandling, labels.statHandling);
        set(els.hintRotate, labels.hintRotate);
        set(els.hintZoom, labels.hintZoom);
        set(els.hintSwitch, labels.hintSwitch);
        set(els.hintSit, labels.hintSit);
        set(els.hintBuy, labels.hintBuy);
        set(els.hintExit, labels.hintExit);
        set(els.confirmTitle, labels.confirmTitle);
        set(els.confirmBody, labels.confirmBody);
        if (labels.confirmYes) els.btnConfirm.textContent = labels.confirmYes;
        if (labels.confirmNo) els.btnCancel.textContent = labels.confirmNo;
    }

    function renderCar(car) {
        if (!car) return;
        els.vehClass.textContent = car.class || 'Vehicle';
        els.vehName.textContent = car.name || '';
        els.vehPrice.textContent = money(car.price);
        const i = String(car.index || 1).padStart(2, '0');
        const t = String(car.total || 1).padStart(2, '0');
        els.vehIndex.textContent = `${i} / ${t}`;

        const s = car.stats || {};
        // reset then set on next frame so the width transition replays
        Object.values(fills).forEach((el) => { el.style.width = '0%'; });
        requestAnimationFrame(() => {
            if (fills.speed) fills.speed.style.width = pct(s.speed);
            if (fills.accel) fills.accel.style.width = pct(s.accel);
            if (fills.braking) fills.braking.style.width = pct(s.braking);
            if (fills.handling) fills.handling.style.width = pct(s.handling);
        });
    }

    function openModal(car) {
        if (car) {
            els.confirmName.textContent = car.name || '';
            els.confirmPrice.textContent = money(car.price);
        }
        els.modal.classList.add('open');
    }
    function closeModal() {
        els.modal.classList.remove('open');
    }

    // ---- message handler ---------------------------------------------------
    window.addEventListener('message', (e) => {
        const data = e.data || {};
        switch (data.action) {
            case 'show':
                applyLabels(data.labels);
                renderCar(data.car);
                closeModal();
                app.classList.remove('hidden');
                break;
            case 'update':
                renderCar(data.car);
                break;
            case 'confirm':
                openModal(data.car);
                break;
            case 'browse':
                closeModal();
                break;
            case 'hide':
                closeModal();
                app.classList.add('hidden');
                break;
        }
    });

    // ---- modal buttons -----------------------------------------------------
    els.btnConfirm.addEventListener('click', () => {
        closeModal();
        post('confirmResult', { confirm: true });
    });
    els.btnCancel.addEventListener('click', () => {
        closeModal();
        post('confirmResult', { confirm: false });
    });

    // ---- dev preview (browser only) ---------------------------------------
    if (!inGame) {
        window.postMessage({
            action: 'show',
            labels: {
                brand: 'Premium Deluxe Motorsport', daily: 'Daily Collection',
                statSpeed: 'Top Speed', statAccel: 'Acceleration',
                statBraking: 'Braking', statHandling: 'Handling',
                hintRotate: 'Look around', hintZoom: 'Zoom', hintSwitch: 'Switch',
                hintSit: 'Sit inside', hintBuy: 'Buy', hintExit: 'Exit',
                confirmTitle: 'Confirm purchase',
                confirmBody: 'Are you sure you want to buy this vehicle?',
                confirmYes: 'Confirm purchase', confirmNo: 'Cancel',
            },
            car: {
                name: 'Truffade Adder', class: 'Super', price: 1000000,
                index: 1, total: 4,
                stats: { speed: 0.95, accel: 0.88, braking: 0.7, handling: 0.82 },
            },
        }, '*');
    }
})();
